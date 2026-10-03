"""Replace slide 4 with an artifact-tool-authored product page.

All other visible pages and their dependencies stay byte-identical. Add the
product source and illustration provenance to the existing bibliography notes.
"""
import importlib.util
import json
import posixpath
import re
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

spec = importlib.util.spec_from_file_location('pptx_package_helpers',Path(__file__).with_name('replace-room-decision-slides.py'))
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
P,R,A,PKG,CT = helpers.P,helpers.R,helpers.A,helpers.PKG,helpers.CT
parse,xml,elements,relpath,target,relationship = helpers.parse,helpers.xml,helpers.elements,helpers.relpath,helpers.target,helpers.relationship

def main(original,addition,output):
    with ZipFile(original) as z:
        old = {n:z.read(n) for n in z.namelist()}
    with ZipFile(addition) as z:
        new = {n:z.read(n) for n in z.namelist()}
    pres = parse(old['ppt/presentation.xml'])
    pres.documentElement.setAttribute('xmlns:r',R)
    prels = parse(old['ppt/_rels/presentation.xml.rels'])
    by_id = {n.getAttribute('Id'):n for n in elements(prels,PKG,'Relationship')}
    ids = elements(pres,P,'sldId')
    assert len(ids)==14
    parts = [target('ppt/presentation.xml',by_id[n.getAttribute('r:id')].getAttribute('Target')) for n in ids]
    assert 'A room model built for decisions' in old[parts[3]].decode()
    assert 'References' in old[parts[13]].decode()
    destinations = {'ppt/slides/slide1.xml':parts[3]}
    notes_master = next(n for n in old if re.fullmatch(r'ppt/notesMasters/[^/]+\.xml',n))
    mapping = {n:notes_master for n in new if re.fullmatch(r'ppt/notesMasters/[^/]+\.xml',n)}
    queue,copy = list(destinations),[]
    while queue:
        part = queue.pop(0)
        if part in mapping:
            continue
        mapping[part] = destinations.get(part,posixpath.join(posixpath.dirname(part),'product-'+posixpath.basename(part)))
        assert mapping[part] not in old or part in destinations
        copy.append(part)
        if relpath(part) in new:
            for n in elements(parse(new[relpath(part)]),PKG,'Relationship'):
                if n.getAttribute('TargetMode')!='External':
                    queue.append(target(part,n.getAttribute('Target')))
    global_ids = []
    for part,data in old.items():
        if part=='ppt/presentation.xml' or re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',part):
            doc = parse(data)
            for tag in ['sldMasterId','sldLayoutId']:
                global_ids.extend(int(n.getAttribute('id')) for n in elements(doc,P,tag))
    next_id = max(global_ids)+1
    for part in copy:
        old[mapping[part]] = new[part]
        if re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',part):
            doc = parse(new[part])
            for n in elements(doc,P,'sldLayoutId'):
                n.setAttribute('id',str(next_id));next_id+=1
            old[mapping[part]] = xml(doc)
        if relpath(part) in new:
            doc = parse(new[relpath(part)])
            for n in elements(doc,PKG,'Relationship'):
                if n.getAttribute('TargetMode')!='External':
                    n.setAttribute('Target',posixpath.relpath(mapping[target(part,n.getAttribute('Target'))],posixpath.dirname(mapping[part])))
            old[relpath(mapping[part])] = xml(doc)
    rid_num = max(int(n.getAttribute('Id')[3:]) for n in elements(prels,PKG,'Relationship') if re.fullmatch(r'rId\d+',n.getAttribute('Id')))+1
    masterlist = elements(pres,P,'sldMasterIdLst')[0]
    for part in copy:
        if re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',part):
            rid = f'rId{rid_num}';rid_num+=1
            relationship(prels,rid,'slideMaster',posixpath.relpath(mapping[part],'ppt'))
            n = pres.createElementNS(P,'p:sldMasterId')
            n.setAttribute('id',str(next_id));next_id+=1
            n.setAttributeNS(R,'r:id',rid);masterlist.appendChild(n)
    old['ppt/presentation.xml'],old['ppt/_rels/presentation.xml.rels'] = xml(pres),xml(prels)
    content = parse(old['[Content_Types].xml'])
    overrides = {n.getAttribute('PartName'):n for n in elements(content,CT,'Override')}
    for n in elements(parse(new['[Content_Types].xml']),CT,'Override'):
        src = n.getAttribute('PartName').lstrip('/')
        if src in copy:
            dest = '/'+mapping[src]
            if dest in overrides:
                overrides[dest].setAttribute('ContentType',n.getAttribute('ContentType'))
            else:
                item = content.importNode(n,True);item.setAttribute('PartName',dest)
                content.documentElement.appendChild(item);overrides[dest]=item
    extensions = {n.getAttribute('Extension') for n in elements(content,CT,'Default')}
    for n in elements(parse(new['[Content_Types].xml']),CT,'Default'):
        if n.getAttribute('Extension') not in extensions:
            content.documentElement.appendChild(content.importNode(n,True));extensions.add(n.getAttribute('Extension'))
    old['[Content_Types].xml'] = xml(content)

    # The bibliography already lists AGENTS.md as source [4]. Preserve its
    # visible objects, hyperlinks and existing notes, and extend provenance.
    notes_rel = next(n for n in elements(parse(old[relpath(parts[13])]),PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    notes_part = target(parts[13],notes_rel.getAttribute('Target'))
    doc = parse(old[notes_part])
    body = next(elements(sp,P,'txBody')[0] for sp in elements(doc,P,'sp') if any(n.getAttribute('type')=='body' for n in elements(sp,P,'ph')))
    lines = [
        'Slide 4 product source [4]: SimuNow (2026), AGENTS.md, sections Project and priorities, Swift and interface guidelines, Physical and result constraints, and Data and task conventions. This page presents the EnergyPlus/OpenFOAM product vision and a native app foundation. Numerical engines and decision evaluation are planned.',
        'Additional illustration provenance: PitchAssets/product-workspace-concept.png, generated with the built-in imagegen tool on 3 October 2026. Full prompt: PitchAssets/product-imagegen-prompt.json. Planned interface concept only, not an actual application screenshot or numerical performance evidence.',
    ]
    for line in lines:
        paragraph = doc.createElementNS(A,'a:p');paragraph.setAttribute('xmlns:a',A)
        run = doc.createElementNS(A,'a:r');text = doc.createElementNS(A,'a:t')
        text.appendChild(doc.createTextNode(line));run.appendChild(text);paragraph.appendChild(run);body.appendChild(paragraph)
    old[notes_part] = xml(doc)

    reachable,queue = {'[Content_Types].xml'},['']
    while queue:
        owner = queue.pop(0)
        if owner in reachable:
            continue
        reachable.add(owner)
        if relpath(owner) in old:
            reachable.add(relpath(owner))
            for n in elements(parse(old[relpath(owner)]),PKG,'Relationship'):
                if n.getAttribute('TargetMode')!='External':
                    queue.append(target(owner,n.getAttribute('Target')))
    released = set(old)-reachable
    assert all(n.startswith(('ppt/media/','ppt/notesSlides/')) for n in released),released
    for n in released:
        del old[n]
    content = parse(old['[Content_Types].xml'])
    for n in elements(content,CT,'Override'):
        if n.getAttribute('PartName').lstrip('/') in released:
            n.parentNode.removeChild(n)
    old['[Content_Types].xml'] = xml(content)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for n,data in old.items():
            z.writestr(n,data)
    print(json.dumps({'slides':14,'changedVisibleSlides':[4],'bibliographyNotesUpdated':notes_part,'releasedParts':sorted(released),'output':output}))

if __name__=='__main__':
    main(*sys.argv[1:])
