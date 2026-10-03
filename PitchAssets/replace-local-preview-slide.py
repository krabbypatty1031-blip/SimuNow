"""Replace only slide 7 with native objects authored using Artifact Tool."""
import importlib.util
import json
import posixpath
import re
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

spec = importlib.util.spec_from_file_location('pptx_package_helpers', Path(__file__).with_name('replace-room-decision-slides.py'))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
P, R, A, PKG, CT = h.P, h.R, h.A, h.PKG, h.CT
parse, xml, elements, relpath, target, relationship = h.parse, h.xml, h.elements, h.relpath, h.target, h.relationship

def notes_body(doc):
    return next(elements(sp, P, 'txBody')[0] for sp in elements(doc, P, 'sp') if any(n.getAttribute('type') == 'body' for n in elements(sp, P, 'ph')))

def main(original, patch, output):
    with ZipFile(original) as z:
        old = {n: z.read(n) for n in z.namelist()}
    with ZipFile(patch) as z:
        new = {n: z.read(n) for n in z.namelist()}
    pres = parse(old['ppt/presentation.xml'])
    prels = {n.getAttribute('Id'): n.getAttribute('Target') for n in elements(parse(old['ppt/_rels/presentation.xml.rels']), PKG, 'Relationship')}
    pages = [target('ppt/presentation.xml', prels[n.getAttribute('r:id')]) for n in elements(pres, P, 'sldId')]
    assert len(pages) == 14
    part, src = pages[6], 'ppt/slides/slide1.xml'
    assert 'Energy and airflow in one model' in old[part].decode()
    assert 'Local preview and scenario comparison' in new[src].decode()
    page = parse(old[part])
    tree = elements(page, P, 'spTree')[0]
    for n in list(tree.childNodes):
        if n.nodeType == n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr', 'grpSpPr'):
            tree.removeChild(n)
    authored = parse(new[src])
    source_tree = elements(authored, P, 'spTree')[0]
    rels, source_rels = parse(old[relpath(part)]), parse(new[relpath(src)])
    next_rid = max([int(n.getAttribute('Id')[3:]) for n in elements(rels, PKG, 'Relationship') if re.fullmatch(r'rId\d+', n.getAttribute('Id'))] or [0]) + 1
    rid_map, media = {}, []
    for n in elements(source_rels, PKG, 'Relationship'):
        if n.getAttribute('Type').endswith('/image'):
            resource = target(src, n.getAttribute('Target'))
            dest = 'ppt/media/local-preview-' + posixpath.basename(resource)
            assert dest not in old
            old[dest] = new[resource]
            media.append(dest)
            rid = f'rId{next_rid}'
            next_rid += 1
            rid_map[n.getAttribute('Id')] = rid
            relationship(rels, rid, 'image', posixpath.relpath(dest, posixpath.dirname(part)))
    objects = [n for n in source_tree.childNodes if n.nodeType == n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr', 'grpSpPr')]
    next_id = max(int(n.getAttribute('id')) for n in elements(page, P, 'cNvPr')) + 1
    ids = {}
    for n in objects:
        for props in elements(n, P, 'cNvPr'):
            source_id = props.getAttribute('id')
            assert source_id not in ids
            ids[source_id] = str(next_id)
            next_id += 1
    for n in objects:
        for props in elements(n, P, 'cNvPr'):
            props.setAttribute('id', ids[props.getAttribute('id')])
        for tag in ('stCxn', 'endCxn'):
            for end in elements(n, A, tag):
                end.setAttribute('id', ids[end.getAttribute('id')])
        for blip in elements(n, A, 'blip'):
            embed = blip.getAttributeNS(R, 'embed')
            assert embed in rid_map
            blip.setAttributeNS(R, 'r:embed', rid_map[embed])
        tree.appendChild(page.importNode(n, True))
    old[part], old[relpath(part)] = xml(page), xml(rels)
    source_note_ref = next(n for n in elements(source_rels, PKG, 'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    source_notes = parse(new[target(src, source_note_ref.getAttribute('Target'))])
    note_ref = next(n for n in elements(rels, PKG, 'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    note_part = target(part, note_ref.getAttribute('Target'))
    notes = parse(old[note_part])
    dest_body = notes_body(notes)
    for n in list(dest_body.childNodes):
        if n.nodeType == n.ELEMENT_NODE and n.localName == 'p':
            dest_body.removeChild(n)
    for n in elements(notes_body(source_notes), A, 'p'):
        dest_body.appendChild(notes.importNode(n, True))
    old[note_part] = xml(notes)
    types = parse(old['[Content_Types].xml'])
    extensions = {n.getAttribute('Extension') for n in elements(types, CT, 'Default')}
    added = False
    for n in elements(parse(new['[Content_Types].xml']), CT, 'Default'):
        if n.getAttribute('Extension') not in extensions:
            types.documentElement.appendChild(types.importNode(n, True))
            extensions.add(n.getAttribute('Extension'))
            added = True
    if added:
        old['[Content_Types].xml'] = xml(types)
    with ZipFile(output, 'w', ZIP_DEFLATED) as z:
        for n, b in old.items():
            z.writestr(n, b)
    print(json.dumps({'slides': 14, 'changedVisibleSlides': [7], 'changedParts': [part, relpath(part), note_part], 'nativeObjectCount': len(objects), 'newMedia': media, 'output': output}))

if __name__ == '__main__':
    main(*sys.argv[1:])
