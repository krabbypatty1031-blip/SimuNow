"""Import an authored scenario page into slide 5 without replacing the template.

Native text/tables and image relationship references are imported into the
existing slide. Other visible slides and all chart dependencies are preserved.
"""
import importlib.util
import json
import posixpath
import re
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

spec=importlib.util.spec_from_file_location('pptx_package_helpers',Path(__file__).with_name('replace-room-decision-slides.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
P,R,A,PKG,CT=h.P,h.R,h.A,h.PKG,h.CT
parse,xml,elements,relpath,target,relationship=h.parse,h.xml,h.elements,h.relpath,h.target,h.relationship

def main(original,patch,output):
    with ZipFile(original) as z:old={n:z.read(n) for n in z.namelist()}
    with ZipFile(patch) as z:new={n:z.read(n) for n in z.namelist()}
    part='ppt/slides/slide4.xml';src='ppt/slides/slide1.xml'
    assert 'A clearer way to configure a room' in old[part].decode()
    page=parse(old[part]);tree=elements(page,P,'spTree')[0]
    for n in list(tree.childNodes):
        if n.nodeType==n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr','grpSpPr'):tree.removeChild(n)
    authored=parse(new[src]);source_tree=elements(authored,P,'spTree')[0]
    rels=parse(old[relpath(part)]);source_rels=parse(new[relpath(src)])
    rid_map={};next_rid=max([int(n.getAttribute('Id')[3:]) for n in elements(rels,PKG,'Relationship') if re.fullmatch(r'rId\d+',n.getAttribute('Id'))] or [0])+1
    media=[]
    for n in elements(source_rels,PKG,'Relationship'):
        if n.getAttribute('Type').endswith('/image'):
            resource=target(src,n.getAttribute('Target'))
            dest='ppt/media/office-scenario-'+posixpath.basename(resource)
            assert dest not in old,dest
            old[dest]=new[resource];media.append(dest)
            rid=f'rId{next_rid}';next_rid+=1;rid_map[n.getAttribute('Id')]=rid
            relationship(rels,rid,'image',posixpath.relpath(dest,posixpath.dirname(part)))
    count=0
    for n in source_tree.childNodes:
        if n.nodeType!=n.ELEMENT_NODE or n.localName in ('nvGrpSpPr','grpSpPr'):continue
        for blip in elements(n,A,'blip'):
            embed=blip.getAttributeNS(R,'embed');assert embed in rid_map
            blip.setAttributeNS(R,'r:embed',rid_map[embed])
        tree.appendChild(page.importNode(n,True));count+=1
    old[part]=xml(page);old[relpath(part)]=xml(rels)
    source_note_ref=next(n for n in elements(source_rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    source_notes=parse(new[target(src,source_note_ref.getAttribute('Target'))])
    note_ref=next(n for n in elements(rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    note_part=target(part,note_ref.getAttribute('Target'));notes=parse(old[note_part])
    def body(doc):
        return next(elements(sp,P,'txBody')[0] for sp in elements(doc,P,'sp') if any(n.getAttribute('type')=='body' for n in elements(sp,P,'ph')))
    dest_body=body(notes)
    for n in list(dest_body.childNodes):
        if n.nodeType==n.ELEMENT_NODE and n.localName=='p':dest_body.removeChild(n)
    for n in elements(body(source_notes),A,'p'):dest_body.appendChild(notes.importNode(n,True))
    old[note_part]=xml(notes)
    # The visible bibliography already provides sources [4] and [6].
    ref='ppt/slides/research-slide2.xml'
    ref_rels=parse(old[relpath(ref)])
    ref_note_ref=next(n for n in elements(ref_rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    ref_note_part=target(ref,ref_note_ref.getAttribute('Target'));doc=parse(old[ref_note_part])
    paragraph=doc.createElementNS(A,'a:p');paragraph.setAttribute('xmlns:a',A)
    run=doc.createElementNS(A,'a:r');text=doc.createElementNS(A,'a:t')
    text.appendChild(doc.createTextNode('Slide 5 office scenario: illustration and fixed inputs are internal hypothetical examples, not a measured office or computed comparison. Source [4] uses the user-approved AGENTS.md product-vision snapshot identified on slide 4; [6] ASHRAE Standard 55 official overview supports the thermal-comfort input factors. Illustration: PitchAssets/office-scenario-pair.png, built-in imagegen, 3 October 2026. Exact generation prompt: PitchAssets/office-scenario-imagegen-prompt.json. Both panels depict the same room with one intended AC-placement change. No numerical results, savings, compliance or preferred candidate are claimed.'))
    run.appendChild(text);paragraph.appendChild(run);body(doc).appendChild(paragraph);old[ref_note_part]=xml(doc)
    types=parse(old['[Content_Types].xml']);extensions={n.getAttribute('Extension') for n in elements(types,CT,'Default')}
    added_types=False
    for n in elements(parse(new['[Content_Types].xml']),CT,'Default'):
        if n.getAttribute('Extension') not in extensions:
            types.documentElement.appendChild(types.importNode(n,True));extensions.add(n.getAttribute('Extension'));added_types=True
    if added_types:old['[Content_Types].xml']=xml(types)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for n,b in old.items():z.writestr(n,b)
    print(json.dumps({'slides':14,'changedVisibleSlides':[5],'nativeObjects':count,'newMedia':media,'updatedNotes':[note_part,ref_note_part],'output':output}))

if __name__=='__main__':main(*sys.argv[1:])
