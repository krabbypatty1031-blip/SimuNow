"""Replace slides 3 and 14 with artifact-tool-authored slides.

Preserve all other slide XML, relationships, media, notes and chart workbooks.
Dependency parts are copied with unique names and package-wide IDs.
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

def elements(doc, ns, tag):
    return list(doc.getElementsByTagNameNS(ns, tag))

def relpath(owner):
    return posixpath.join(posixpath.dirname(owner), '_rels', posixpath.basename(owner)+'.rels')

def target(owner, relative):
    return posixpath.normpath(posixpath.join(posixpath.dirname(owner), relative)).lstrip('/')

def rename(part):
    return posixpath.join(posixpath.dirname(part), 'decision-'+posixpath.basename(part))

def relationship(doc, rid, kind, destination, external=False):
    r = doc.createElementNS(PKG, 'Relationship')
    r.setAttribute('Id', rid)
    r.setAttribute('Type', R+'/'+kind)
    r.setAttribute('Target', destination)
    if external:
        r.setAttribute('TargetMode', 'External')
    doc.documentElement.appendChild(r)

def main(original, additions, output):
    with ZipFile(original) as z:
        old = {n:z.read(n) for n in z.namelist()}
    with ZipFile(additions) as z:
        new = {n:z.read(n) for n in z.namelist()}
    pres = parse(old['ppt/presentation.xml'])
    pres.documentElement.setAttribute('xmlns:r', R)
    prels = parse(old['ppt/_rels/presentation.xml.rels'])
    by_id = {n.getAttribute('Id'):n for n in elements(prels,PKG,'Relationship')}
    ids = elements(pres,P,'sldId')
    assert len(ids)==14, 'Expected the current fourteen-slide researched deck.'
    parts = [target('ppt/presentation.xml',by_id[n.getAttribute('r:id')].getAttribute('Target')) for n in ids]
    assert 'One room. Different experiences' in old[parts[2]].decode('utf-8')
    assert 'References' in old[parts[13]].decode('utf-8')
    destinations = {'ppt/slides/slide1.xml':parts[2], 'ppt/slides/slide2.xml':parts[13]}
    old_notes_master = next(n for n in old if re.fullmatch(r'ppt/notesMasters/[^/]+\.xml',n))
    mapping = {n:old_notes_master for n in new if re.fullmatch(r'ppt/notesMasters/[^/]+\.xml',n)}
    queue = list(destinations)
    copy = []
    while queue:
        part = queue.pop(0)
        if part in mapping:
            continue
        mapping[part] = destinations.get(part,rename(part))
        assert mapping[part] not in old or part in destinations, ('Dependency name collision',mapping[part])
        copy.append(part)
        rel = relpath(part)
        if rel in new:
            for r in elements(parse(new[rel]),PKG,'Relationship'):
                if r.getAttribute('TargetMode')!='External':
                    queue.append(target(part,r.getAttribute('Target')))

    global_ids = []
    for part,data in old.items():
        if part=='ppt/presentation.xml' or re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',part):
            d = parse(data)
            for tag in ['sldMasterId','sldLayoutId']:
                global_ids.extend(int(n.getAttribute('id')) for n in elements(d,P,tag))
    next_global_id = max(global_ids)+1
    for part in copy:
        old[mapping[part]] = new[part]
        if re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',part):
            master = parse(old[mapping[part]])
            for n in elements(master,P,'sldLayoutId'):
                n.setAttribute('id',str(next_global_id))
                next_global_id += 1
            old[mapping[part]] = xml(master)
        rel = relpath(part)
        if rel in new:
            doc = parse(new[rel])
            for r in elements(doc,PKG,'Relationship'):
                if r.getAttribute('TargetMode')!='External':
                    r.setAttribute('Target',posixpath.relpath(mapping[target(part,r.getAttribute('Target'))],posixpath.dirname(mapping[part])))
            old[relpath(mapping[part])] = xml(doc)

    nr = max([int(n.getAttribute('Id')[3:]) for n in elements(prels,PKG,'Relationship') if re.fullmatch(r'rId\d+',n.getAttribute('Id'))],default=0)+1
    masterlist = elements(pres,P,'sldMasterIdLst')[0]
    for source in copy:
        if re.fullmatch(r'ppt/slideMasters/[^/]+\.xml',source):
            rid = f'rId{nr}'
            nr += 1
            relationship(prels,rid,'slideMaster',posixpath.relpath(mapping[source],'ppt'))
            n = pres.createElementNS(P,'p:sldMasterId')
            n.setAttribute('id',str(next_global_id))
            next_global_id += 1
            n.setAttributeNS(R,'r:id',rid)
            masterlist.appendChild(n)
    old['ppt/presentation.xml'] = xml(pres)
    old['ppt/_rels/presentation.xml.rels'] = xml(prels)

    content = parse(old['[Content_Types].xml'])
    overrides = {n.getAttribute('PartName'):n for n in elements(content,CT,'Override')}
    for n in elements(parse(new['[Content_Types].xml']),CT,'Override'):
        src = n.getAttribute('PartName').lstrip('/')
        if src in copy:
            destination = '/'+mapping[src]
            if destination in overrides:
                overrides[destination].setAttribute('ContentType',n.getAttribute('ContentType'))
            else:
                item = content.importNode(n,True)
                item.setAttribute('PartName',destination)
                content.documentElement.appendChild(item)
                overrides[destination] = item
    extensions = {n.getAttribute('Extension') for n in elements(content,CT,'Default')}
    for n in elements(parse(new['[Content_Types].xml']),CT,'Default'):
        if n.getAttribute('Extension') not in extensions:
            content.documentElement.appendChild(content.importNode(n,True))
            extensions.add(n.getAttribute('Extension'))
    old['[Content_Types].xml'] = xml(content)

    links = {
        'ref1-link':'https://www.emsd.gov.hk/filemanager/en/content_762/HKEEUD2026.pdf',
        'ref2-link':'https://www.iea.org/commentaries/cooling-a-hotter-world-el-nino-meets-strong-growth-in-global-electricity-demand',
        'ref6-link':'https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy',
        'ref7-link':'https://energyplus.readthedocs.io/en/latest/guides/engineering-reference/17.1-zone-internal-gains.html',
    }
    part = parts[13]
    doc = parse(old[part])
    doc.documentElement.setAttribute('xmlns:r',R)
    rel = parse(old[relpath(part)])
    for sp in elements(doc,P,'sp'):
        props = elements(sp,P,'cNvPr')
        if not props or props[0].getAttribute('name') not in links:
            continue
        name = props[0].getAttribute('name')
        rid = 'rId-'+name
        relationship(rel,rid,'hyperlink',links[name],True)
        for run in elements(sp,A,'r'):
            rp = elements(run,A,'rPr')[0]
            h = doc.createElementNS(A,'a:hlinkClick')
            h.setAttributeNS(R,'r:id',rid)
            rp.appendChild(h)
    old[part] = xml(doc)
    old[relpath(part)] = xml(rel)

    # Replaced pages release their former notes and any uniquely owned artwork.
    # Keep every registered master and every dependency of the other pages.
    reachable = {'[Content_Types].xml'}
    queue = ['']
    while queue:
        owner = queue.pop(0)
        if owner in reachable:
            continue
        reachable.add(owner)
        rel = relpath(owner)
        if rel in old:
            reachable.add(rel)
            for n in elements(parse(old[rel]),PKG,'Relationship'):
                if n.getAttribute('TargetMode')!='External':
                    queue.append(target(owner,n.getAttribute('Target')))
    released = set(old)-reachable
    assert all(n.startswith(('ppt/media/','ppt/notesSlides/')) for n in released), ('Unexpected unowned part',released)
    for name in released:
        del old[name]
    content = parse(old['[Content_Types].xml'])
    for n in elements(content,CT,'Override'):
        if n.getAttribute('PartName').lstrip('/') in released:
            n.parentNode.removeChild(n)
    old['[Content_Types].xml'] = xml(content)
    with ZipFile(output,'w',ZIP_DEFLATED) as z:
        for name,data in old.items():
            z.writestr(name,data)
    print(json.dumps({'slides':14,'replacedPositions':[3,14],'preservedSlideCount':12,'nativeTableSlide':3,'releasedParts':sorted(released),'output':output}))

if __name__=='__main__':
    main(*sys.argv[1:])
