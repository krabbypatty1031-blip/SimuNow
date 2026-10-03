"""Merge artifact-tool-authored research slides into a preserved 12-slide deck.

Only old page-number runs and package registration change. Old slide objects,
media, layouts and speaker notes remain intact. Uses DOM to preserve OOXML
namespace prefixes. Every copied dependency has its relationship rewritten.
"""
import json
import posixpath
import re
import sys
from zipfile import ZipFile, ZIP_DEFLATED
from defusedxml import minidom

P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'

def parse(data):
    return minidom.parseString(data)

def xml(doc):
    return doc.toxml(encoding='UTF-8')

def relpath(owner):
    return posixpath.join(posixpath.dirname(owner), '_rels', posixpath.basename(owner)+'.rels')

def target(owner, relative):
    return posixpath.normpath(posixpath.join(posixpath.dirname(owner), relative)).lstrip('/')

def rename(part):
    return posixpath.join(posixpath.dirname(part), 'research-'+posixpath.basename(part))

def elements(doc, ns, tag):
    return list(doc.getElementsByTagNameNS(ns, tag))

def relationship(doc, rid, kind, destination, external=False):
    r=doc.createElementNS(PKG,'Relationship')
    r.setAttribute('Id',rid)
    r.setAttribute('Type',R+'/'+kind)
    r.setAttribute('Target',destination)
    if external:
        r.setAttribute('TargetMode','External')
    doc.documentElement.appendChild(r)

def main(original, additions, output):
    with ZipFile(original) as z:
        old={n:z.read(n) for n in z.namelist()}
    global_ids=[]
    for part,data in old.items():
        if part=='ppt/presentation.xml' or re.fullmatch(r'ppt/slideMasters/slideMaster\d+\.xml',part):
            d=parse(data)
            for tag in ['sldMasterId','sldLayoutId']:
                global_ids.extend(int(n.getAttribute('id')) for n in elements(d,P,tag))
    next_global_id=max(global_ids)+1
    with ZipFile(additions) as z:
        new={n:z.read(n) for n in z.namelist()}
    pres=parse(old['ppt/presentation.xml'])
    pres.documentElement.setAttribute('xmlns:r',R)
    ids=elements(pres,P,'sldId')
    assert len(ids)==12, 'Input must be the original 12-slide deck, before this insertion.'
    old_rels=parse(old['ppt/_rels/presentation.xml.rels'])
    old_by_id={r.getAttribute('Id'):r for r in elements(old_rels,PKG,'Relationship')}
    original_parts=[target('ppt/presentation.xml',old_by_id[n.getAttribute('r:id')].getAttribute('Target')) for n in ids]
    expected=['Simulate first.','One room. Different experiences']
    for part,needle in zip(original_parts,expected):
        assert needle in old[part].decode('utf-8'), 'Unexpected source deck.'
    old_notes_master=next(n for n in old if re.fullmatch(r'ppt/notesMasters/notesMaster\d+\.xml',n))
    source_notes_masters=[n for n in new if re.fullmatch(r'ppt/notesMasters/notesMaster\d+\.xml',n)]
    mapping={n:old_notes_master for n in source_notes_masters}
    queue=['ppt/slides/slide1.xml','ppt/slides/slide2.xml']
    copy=[]
    while queue:
        part=queue.pop(0)
        if part in mapping:
            continue
        mapping[part]=rename(part)
        copy.append(part)
        rel=relpath(part)
        if rel in new:
            for r in elements(parse(new[rel]),PKG,'Relationship'):
                if r.getAttribute('TargetMode')!='External':
                    queue.append(target(part,r.getAttribute('Target')))
    for part in copy:
        old[mapping[part]]=new[part]
        if re.fullmatch(r'ppt/slideMasters/slideMaster\d+\.xml',part):
            master=parse(old[mapping[part]])
            for n in elements(master,P,'sldLayoutId'):
                n.setAttribute('id',str(next_global_id));next_global_id+=1
            old[mapping[part]]=xml(master)
        rel=relpath(part)
        if rel in new:
            doc=parse(new[rel])
            for r in elements(doc,PKG,'Relationship'):
                if r.getAttribute('TargetMode')!='External':
                    r.setAttribute('Target',posixpath.relpath(mapping[target(part,r.getAttribute('Target'))],posixpath.dirname(mapping[part])))
            old[relpath(mapping[part])]=xml(doc)

    # Structural insertion happens before any text or hyperlink edits.
    rid_nums=[int(r.getAttribute('Id')[3:]) for r in elements(old_rels,PKG,'Relationship') if re.fullmatch(r'rId\d+',r.getAttribute('Id'))]
    nr=max(rid_nums,default=0)+1
    nid=max(int(n.getAttribute('id')) for n in ids)+1
    slist=elements(pres,P,'sldIdLst')[0]
    for source,after_first in [('ppt/slides/slide1.xml',True),('ppt/slides/slide2.xml',False)]:
        rid=f'rId{nr}'; nr+=1
        relationship(old_rels,rid,'slide',posixpath.relpath(mapping[source],'ppt'))
        n=pres.createElementNS(P,'p:sldId'); n.setAttribute('id',str(nid)); nid+=1; n.setAttributeNS(R,'r:id',rid)
        if after_first:
            slist.insertBefore(n,ids[1])
        else:
            slist.appendChild(n)
    masterlist=elements(pres,P,'sldMasterIdLst')[0]
    for source in copy:
        if re.fullmatch(r'ppt/slideMasters/slideMaster\d+\.xml',source):
            rid=f'rId{nr}'; nr+=1
            relationship(old_rels,rid,'slideMaster',posixpath.relpath(mapping[source],'ppt'))
            n=pres.createElementNS(P,'p:sldMasterId'); n.setAttribute('id',str(next_global_id)); next_global_id+=1; n.setAttributeNS(R,'r:id',rid)
            masterlist.appendChild(n)
    old['ppt/presentation.xml']=xml(pres)
    old['ppt/_rels/presentation.xml.rels']=xml(old_rels)
    content=parse(old['[Content_Types].xml'])
    source_ct=parse(new['[Content_Types].xml'])
    for n in elements(source_ct,CT,'Override'):
        src=n.getAttribute('PartName').lstrip('/')
        if src in copy:
            item=content.importNode(n,True)
            item.setAttribute('PartName','/'+mapping[src])
            content.documentElement.appendChild(item)
    extensions={n.getAttribute('Extension') for n in elements(content,CT,'Default')}
    for n in elements(source_ct,CT,'Default'):
        if n.getAttribute('Extension') not in extensions:
            content.documentElement.appendChild(content.importNode(n,True))
    old['[Content_Types].xml']=xml(content)
    if 'docProps/app.xml' in old:
        app=parse(old['docProps/app.xml'])
        for n in app.getElementsByTagNameNS('http://schemas.openxmlformats.org/officeDocument/2006/extended-properties','Slides'):
            n.firstChild.data='14'
        for n in app.getElementsByTagNameNS('http://schemas.openxmlformats.org/officeDocument/2006/extended-properties','Notes'):
            n.firstChild.data='14'
        old['docProps/app.xml']=xml(app)

    # Shift page markers only, never workflow labels or table content.
    changed_pages=[]
    for old_number,part in enumerate(original_parts,1):
        if old_number==1:
            continue
        doc=parse(old[part])
        changed=0
        for sp in elements(doc,P,'sp'):
            props=elements(sp,P,'cNvPr')
            if props and props[0].getAttribute('name') in (f'page-{old_number}','closing-page'):
                t=elements(sp,A,'t')
                assert len(t)==1 and t[0].firstChild.data==f'{old_number:02}'
                t[0].firstChild.data=f'{old_number+1:02}'; changed+=1
        assert changed==1,(old_number,changed)
        old[part]=xml(doc); changed_pages.append(part)

    links={'ref1-link':'https://www.emsd.gov.hk/filemanager/en/content_762/HKEEUD2026.pdf',
           'ref2-link':'https://www.iea.org/commentaries/cooling-a-hotter-world-el-nino-meets-strong-growth-in-global-electricity-demand'}
    part=mapping['ppt/slides/slide2.xml']
    doc=parse(old[part]); rel=parse(old[relpath(part)])
    doc.documentElement.setAttribute('xmlns:r',R)
    for sp in elements(doc,P,'sp'):
        props=elements(sp,P,'cNvPr')
        if not props or props[0].getAttribute('name') not in links:
            continue
        name=props[0].getAttribute('name'); rid='rId-'+name
        relationship(rel,rid,'hyperlink',links[name],True)
        for run in elements(sp,A,'r'):
            rp=elements(run,A,'rPr')[0]
            h=doc.createElementNS(A,'a:hlinkClick');h.setAttributeNS(R,'r:id',rid);rp.appendChild(h)
    old[part]=xml(doc);old[relpath(part)]=xml(rel)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for name,data in old.items():
            z.writestr(name,data)
    print(json.dumps({'slides':14,'newCharts':2,'insertedPosition':2,'bibliographyPosition':14,'oldPagesRenumbered':len(changed_pages),'preservedOriginalParts':len(original_parts),'output':output}))

if __name__=='__main__':
    main(*sys.argv[1:])
