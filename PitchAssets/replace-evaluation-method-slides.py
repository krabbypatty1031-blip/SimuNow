"""Import the method diagram and expanded bibliography into existing slides.

Keep slide order, layouts, masters, other pages and chart workbooks unchanged.
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

def body(doc):
    return next(elements(sp,P,'txBody')[0] for sp in elements(doc,P,'sp') if any(n.getAttribute('type')=='body' for n in elements(sp,P,'ph')))

def main(original,patch,output):
    with ZipFile(original) as z:old={n:z.read(n) for n in z.namelist()}
    with ZipFile(patch) as z:new={n:z.read(n) for n in z.namelist()}
    assert 'Designed around the room' in old['ppt/slides/slide5.xml'].decode()
    assert 'References' in old['ppt/slides/research-slide2.xml'].decode()
    updated_notes=[];media=[];counts=[]
    for src,part,replace_notes in [('ppt/slides/slide1.xml','ppt/slides/slide5.xml',True),('ppt/slides/slide2.xml','ppt/slides/research-slide2.xml',False)]:
        page=parse(old[part]);tree=elements(page,P,'spTree')[0]
        for n in list(tree.childNodes):
            if n.nodeType==n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr','grpSpPr'):tree.removeChild(n)
        authored=parse(new[src]);source_tree=elements(authored,P,'spTree')[0]
        rels=parse(old[relpath(part)]);source_rels=parse(new[relpath(src)])
        next_rid=max([int(n.getAttribute('Id')[3:]) for n in elements(rels,PKG,'Relationship') if re.fullmatch(r'rId\d+',n.getAttribute('Id'))] or [0])+1
        rid_map={}
        for n in elements(source_rels,PKG,'Relationship'):
            if n.getAttribute('Type').endswith('/image'):
                resource=target(src,n.getAttribute('Target'));dest='ppt/media/evaluation-method-'+posixpath.basename(resource)
                assert dest not in old,dest
                old[dest]=new[resource];media.append(dest)
                rid=f'rId{next_rid}';next_rid+=1;rid_map[n.getAttribute('Id')]=rid
                relationship(rels,rid,'image',posixpath.relpath(dest,posixpath.dirname(part)))
        objects=[n for n in source_tree.childNodes if n.nodeType==n.ELEMENT_NODE and n.localName not in ('nvGrpSpPr','grpSpPr')]
        next_id=max(int(n.getAttribute('id')) for n in elements(page,P,'cNvPr'))+1
        ids={}
        for n in objects:
            for props in elements(n,P,'cNvPr'):
                old_id=props.getAttribute('id');assert old_id not in ids
                ids[old_id]=str(next_id);next_id+=1
        for n in objects:
            for props in elements(n,P,'cNvPr'):props.setAttribute('id',ids[props.getAttribute('id')])
            for tag in ('stCxn','endCxn'):
                for end in elements(n,A,tag):end.setAttribute('id',ids[end.getAttribute('id')])
            for blip in elements(n,A,'blip'):
                embed=blip.getAttributeNS(R,'embed');assert embed in rid_map
                blip.setAttributeNS(R,'r:embed',rid_map[embed])
            tree.appendChild(page.importNode(n,True))
        old[part]=xml(page);old[relpath(part)]=xml(rels);counts.append(len(objects))
        source_note_ref=next(n for n in elements(source_rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
        source_notes=parse(new[target(src,source_note_ref.getAttribute('Target'))])
        note_ref=next(n for n in elements(rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/notesSlide'))
        note_part=target(part,note_ref.getAttribute('Target'));notes=parse(old[note_part]);dest_body=body(notes)
        if replace_notes:
            for n in list(dest_body.childNodes):
                if n.nodeType==n.ELEMENT_NODE and n.localName=='p':dest_body.removeChild(n)
        for n in elements(body(source_notes),A,'p'):dest_body.appendChild(notes.importNode(n,True))
        old[note_part]=xml(notes);updated_notes.append(note_part)

    links={
        'ref1-link':'https://www.emsd.gov.hk/filemanager/en/content_762/HKEEUD2026.pdf',
        'ref2-link':'https://www.iea.org/commentaries/cooling-a-hotter-world-el-nino-meets-strong-growth-in-global-electricity-demand',
        'ref6-link':'https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy',
        'ref7-link':'https://energyplus.readthedocs.io/en/latest/guides/engineering-reference/17.1-zone-internal-gains.html',
        'ref8-link':'https://energyplus.readthedocs.io/en/stable/quick_start/quick_start.html',
        'ref9-link':'https://doc.openfoam.com/2306/tools/processing/solvers/rtm/heat-transfer/buoyantSimpleFoam/',
    }
    part='ppt/slides/research-slide2.xml';doc=parse(old[part]);doc.documentElement.setAttribute('xmlns:r',R);rels=parse(old[relpath(part)])
    by_url={n.getAttribute('Target'):n.getAttribute('Id') for n in elements(rels,PKG,'Relationship') if n.getAttribute('Type').endswith('/hyperlink')}
    for sp in elements(doc,P,'sp'):
        props=elements(sp,P,'cNvPr')
        if not props or props[0].getAttribute('name') not in links:continue
        name=props[0].getAttribute('name');url=links[name];rid=by_url.get(url)
        if not rid:
            rid='rId-method-'+name;relationship(rels,rid,'hyperlink',url,True);by_url[url]=rid
        for run in elements(sp,A,'r'):
            rp=elements(run,A,'rPr')[0];link=doc.createElementNS(A,'a:hlinkClick');link.setAttributeNS(R,'r:id',rid);rp.appendChild(link)
    old[part]=xml(doc);old[relpath(part)]=xml(rels)
    # PNG and other patch extensions already exist in this deck. Keep the
    # content-types file byte-identical unless a genuinely new type is needed.
    types=parse(old['[Content_Types].xml']);extensions={n.getAttribute('Extension') for n in elements(types,CT,'Default')};added=False
    for n in elements(parse(new['[Content_Types].xml']),CT,'Default'):
        if n.getAttribute('Extension') not in extensions:
            types.documentElement.appendChild(types.importNode(n,True));extensions.add(n.getAttribute('Extension'));added=True
    if added:old['[Content_Types].xml']=xml(types)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for n,b in old.items():z.writestr(n,b)
    print(json.dumps({'slides':14,'changedVisibleSlides':[6,14],'nativeObjectCounts':counts,'newMedia':media,'updatedNotes':updated_notes,'bibliographyLinks':len(links),'output':output}))

if __name__=='__main__':main(*sys.argv[1:])
