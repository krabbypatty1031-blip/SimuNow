"""Replace only the annotated text region on slide 4 with native diagram objects.

The artifact-tool patch supplies shapes/connectors. Existing objects outside
the region, relationships, media, masters and other pages remain untouched.
"""
import importlib.util
import json
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

spec=importlib.util.spec_from_file_location('pptx_package_helpers',Path(__file__).with_name('replace-room-decision-slides.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
P,A,PKG=h.P,h.A,h.PKG
parse,xml,elements,relpath,target=h.parse,h.xml,h.elements,h.relpath,h.target

def main(original,patch,output):
    with ZipFile(original) as z:
        data={n:z.read(n) for n in z.namelist()}
    with ZipFile(patch) as z:
        diagram=parse(z.read('ppt/slides/slide1.xml'))
    part='ppt/slides/slide3.xml'
    slide=parse(data[part]);tree=elements(slide,P,'spTree')[0]
    assert 'Introducing SimuNow' in data[part].decode()
    selected={'6','9','10','11','12','13','14','15','16'}
    removed=[]
    for child in list(tree.childNodes):
        if child.nodeType!=child.ELEMENT_NODE:
            continue
        props=elements(child,P,'cNvPr')
        if props and props[0].getAttribute('id') in selected:
            removed.append(props[0].getAttribute('id'));tree.removeChild(child)
    assert set(removed)==selected,removed
    source_tree=elements(diagram,P,'spTree')[0]
    objects=[n for n in source_tree.childNodes if n.nodeType==n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr','grpSpPr')]
    next_id=max(int(n.getAttribute('id')) for n in elements(slide,P,'cNvPr'))+1
    id_map={}
    for obj in objects:
        for n in elements(obj,P,'cNvPr'):
            old_id=n.getAttribute('id');assert old_id not in id_map
            id_map[old_id]=str(next_id);next_id+=1
    for obj in objects:
        for n in elements(obj,P,'cNvPr'):
            n.setAttribute('id',id_map[n.getAttribute('id')])
        for tag in ('stCxn','endCxn'):
            for n in elements(obj,A,tag):
                assert n.getAttribute('id') in id_map
                n.setAttribute('id',id_map[n.getAttribute('id')])
        tree.appendChild(slide.importNode(obj,True))
    data[part]=xml(slide)
    rel=parse(data[relpath(part)])
    note_ref=next(n for n in elements(rel,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
    note_part=target(part,note_ref.getAttribute('Target'))
    notes=parse(data[note_part])
    body=next(elements(sp,P,'txBody')[0] for sp in elements(notes,P,'sp') if any(n.getAttribute('type')=='body' for n in elements(sp,P,'ph')))
    text='Functional schematic: shared room/HVAC inputs feed the two planned analyses. A common evidence check precedes comparison of comfort at occupied seats, representative-day electricity and tariff-based operating cost. Lines indicate information relationships, not an implemented transient coupling or a measured performance result. Source [4] remains the AGENTS.md snapshot cited above. Other necessary comfort inputs are described in the preceding notes. The diagram labels, nodes and attached connectors are native editable PowerPoint objects.'
    paragraph=notes.createElementNS(A,'a:p');paragraph.setAttribute('xmlns:a',A)
    run=notes.createElementNS(A,'a:r');t=notes.createElementNS(A,'a:t')
    t.appendChild(notes.createTextNode(text));run.appendChild(t);paragraph.appendChild(run);body.appendChild(paragraph)
    data[note_part]=xml(notes)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for n,b in data.items():z.writestr(n,b)
    print(json.dumps({'changedSlide':4,'removedObjectIds':sorted(selected),'nativeDiagramObjects':len(objects),'nativeConnectors':len(elements(diagram,P,'cxnSp')),'updatedNotes':note_part,'output':output}))

if __name__=='__main__':main(*sys.argv[1:])
