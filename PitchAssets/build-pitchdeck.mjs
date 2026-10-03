import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

// Run with the bundled presentation runtime. Set PROJECT_ROOT when staging
// this source outside the repository. All project asset paths are relative.
const projectRoot = process.env.PROJECT_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceDir = process.env.PITCH_WORK_DIR;
const skillDir = process.env.PRESENTATIONS_SKILL_DIR;
const pythonExecutable = process.env.PRESENTATIONS_PYTHON;
if (![workspaceDir, skillDir, pythonExecutable].every(p => p && path.isAbsolute(p))) {
  throw new Error('Set PITCH_WORK_DIR, PRESENTATIONS_SKILL_DIR and PRESENTATIONS_PYTHON to absolute runtime paths.');
}
const { resolvePresentationFont, finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
const FONT = resolvePresentationFont({ fontFamily: 'Arial' });
const C = { white: '#FFFFFF', ink: '#20282C', secondary: '#536069', muted: '#64727A', pale: '#F1F4F5', line: '#D7DFE3', teal: '#277F89', cyan: '#57BCC7' };
const W = 1280, H = 720;
const presentation = Presentation.create({ slideSize: { width: W, height: H } });
presentation.theme.colorScheme = {
  name: 'SimuNow Architectural Light',
  themeColors: { accent1:C.teal, accent2:C.cyan, accent3:'#788D98', accent4:'#BDC9CE', accent5:'#D6E6E8', accent6:'#6B7880', bg1:C.white, bg2:C.pale, tx1:C.ink, tx2:C.secondary, dk1:C.ink, dk2:C.secondary, lt1:C.white, lt2:C.pale, hlink:C.teal, folHlink:C.secondary }
};
const staging = path.join(workspaceDir, 'build');
const output = path.join(workspaceDir, 'output');
await fs.mkdir(staging, { recursive: true });
await fs.mkdir(output, { recursive: true });
const imageBytes = Object.fromEntries(await Promise.all(['cover-architecture-airflow', 'seat-airflow-study', 'room-model-exploded'].map(async name => [name, new Uint8Array(await fs.readFile(path.join(projectRoot, 'PitchAssets', `${name}.png`)))])));

function text(owner, name, value, x, y, width, height, size = 26, opts = {}) {
  const shape = owner.shapes.add({ geometry:'textbox', name, position:{left:x, top:y, width, height}, fill:'none', line:{fill:'none', width:0} });
  shape.text = value;
  shape.text.style = { typeface:FONT, fontSize:size, color:opts.color ?? C.ink, bold:opts.bold ?? false, alignment:opts.align ?? 'left', verticalAlignment:'top', autoFit:'none', wrap:'square', insets:{left:0,right:0,top:0,bottom:0}, ...(opts.style ?? {}) };
  return shape;
}
function picture(slide, key, x, y, width, height, alt, fit = 'contain') {
  return slide.images.add({blob:imageBytes[key],contentType:'image/png',alt,fit,position:{left:x,top:y,width,height}});
}
const master = presentation.masters.add('SimuNow — Architectural Light');
master.background.fill = C.white;
text(master,'simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
const layoutNames = ['Cover — Architectural hero','Statement — Spatial visual','Split — Model and inputs','Process — Four steps','Product — Workflow columns','Method — Two engines','Evidence — Comparison table','Evidence — Quality gates','Value — Decision columns','Progress — Status table','Roadmap — Four milestones','Closing — Architectural hero'];
const layouts = new Map();
for (const name of layoutNames) {
  const layout = presentation.layouts.add(name);
  layout.setParentLayoutId(master.id);
  const isHero = name.startsWith('Cover') || name.startsWith('Closing');
  const p = layout.placeholders.add({type:'title', index:0, geometry:'textbox', text:'', position:isHero ? {left:72,top:191,width:460,height:178} : {left:72,top:107,width:1136,height:120},fill:'none',line:{fill:'none',width:0}});
  p.text.style = {typeface:FONT,fontSize:isHero?68:52,bold:true,color:C.ink,autoFit:'none',verticalAlignment:'top',insets:{left:0,right:0,top:0,bottom:0}};
  // Reusable body and picture placeholders are empty until a new slide uses them.
  const b = layout.placeholders.add({type:'body',index:1,geometry:'textbox',text:'',position:isHero?{left:74,top:398,width:410,height:110}:{left:72,top:242,width:440,height:350},fill:'none',line:{fill:'none',width:0}});
  b.text.style={typeface:FONT,fontSize:26,color:C.secondary,autoFit:'none',insets:{left:0,right:0,top:0,bottom:0}};
  layouts.set(name,layout);
}
function slide(index, layoutName, title, footer, notes, titleSize=52) {
  const s=presentation.slides.add({layoutId:layouts.get(layoutName).id});
  s.background.fill=C.white;
  const heading=s.placeholders.getItem('title');
  heading.text=title;
  heading.text.style={typeface:FONT,fontSize:titleSize,bold:true,color:C.ink,autoFit:'none',insets:{left:0,right:0,top:0,bottom:0}};
  const isHero=layoutName.startsWith('Cover')||layoutName.startsWith('Closing');
  if (!isHero) {
    text(s,`page-${index}`,String(index).padStart(2,'0'),1166,665,42,24,15,{color:C.muted,align:'right'});
    if (footer) text(s,`context-${index}`,footer,72,665,1064,26,16,{color:C.muted});
  }
  s.speakerNotes.textFrame.setText(notes);
  return s;
}
function headingBody(s,name,title,body,x,y,width=340,size=28) {
  text(s,`${name}-title`,title,x,y,width,48,size,{bold:true});
  text(s,`${name}-body`,body,x,y+55,width,95,24,{color:C.secondary});
}
function connect(s,a,b) {
  s.shapes.connect(a,b,{kind:'straight',fromSide:'right',toSide:'left',line:{fill:C.line,width:1.7},tail:{type:'triangle',width:'sm',length:'sm'}});
}
function nativeTable(s, name, values, columnWidths, y, height, fontSize=23) {
  const table=s.tables.add({rows:values.length,columns:values[0].length,left:72,top:y,width:1136,height,values,columnWidths});
  table.styleOptions={headerRow:true,bandedRows:false};
  for(let r=0;r<values.length;r++) for(let col=0;col<values[0].length;col++) {
    const cell=table.getCell(r,col);
    cell.fill=r===0?C.pale:C.white;
    cell.text.style={typeface:FONT,fontSize:fontSize,bold:r===0||col===0,color:r===0?C.ink:col===0?C.ink:C.secondary,alignment:'left',verticalAlignment:'middle',autoFit:'none',insets:{left:16,right:12,top:12,bottom:12}};
  }
  table.cells.block({row:0,column:0,rowCount:values.length,columnCount:values[0].length}).assign({
    margins:{left:16,right:12,top:12,bottom:12},
    borders:{top:{color:C.white,width:0},bottom:{color:C.line,width:0.7},left:{color:C.white,width:0},right:{color:C.white,width:0}}
  });
  return table;
}
const scope='Source: Plans/References/01-product-scope.md; Plans/References/03-experience-design.md. All capabilities on this slide describe the planned product unless explicitly marked as implemented.';
const physics='Source: Plans/References/05-computation-and-decision.md; Plans/References/02-architecture.md. EnergyPlus and OpenFOAM are planned adapters, not connected engines. Representative-day energy and a representative steady-state CFD condition are distinct outputs; this is not a transient or dynamically coupled prediction.';

// 1 — Final cover design: image as background, native editable typography.
{
  const s=slide(1,layoutNames[0],'Simulate first.\nDesign better.','Concept illustration · P0 product foundation',`Cover visual generated with the built-in imagegen tool. Asset: PitchAssets/cover-architecture-airflow.png. Image shows artistic airflow trajectories, not CFD or measured results. Headline and subtitle express the planned product vision: compare HVAC decisions through a common spatial model connecting airflow, energy and seat-level comfort. Numerical engine integration and comfort evaluation are not yet implemented. Sources: README.md; Plans/References/01-product-scope.md; Plans/References/02-architecture.md; Plans/Delivery/status.md.`,68);
  picture(s,'cover-architecture-airflow',0,0,W,H,'White architectural office cutaway with geometric construction lines and conceptual airflow streamlines','cover');
  // Images added later sit above placeholders; keep editable foreground on top.
  s.placeholders.getItem('title').bringToFront();
  text(s,'cover-brand','SimuNow',72,48,300,42,28,{bold:true});
  text(s,'cover-subtitle','Airflow and energy in one model.\nComfort insights for every seat.',74,398,420,105,25,{color:C.secondary});
  text(s,'cover-disclosure','Concept illustration · P0 product foundation',72,665,720,25,16,{color:C.muted});
  text(s,'cover-page','01',1166,665,42,24,15,{color:C.muted,align:'right'});
}
// 2 — Problem / spatial illustration layout.
{
  const s=slide(2,layoutNames[1],'One room. Different experiences','Concept seat study · not a simulation result',`${scope}\nArt generated with built-in imagegen. Asset: PitchAssets/seat-airflow-study.png. Analysis rings and streamlines are illustrative. Do not infer temperature, draught risk or thermal comfort from this artwork. Future evidence: measured or valid modeled differences among seat locations.`);
  headingBody(s,'air-distribution','Air distribution','A room average cannot describe every seat.',72,252,360,29);
  headingBody(s,'local-exposure','Local exposure','Furniture and placement shape the flow.',72,416,360,29);
  picture(s,'seat-airflow-study',470,195,758,436,'Concept overhead office study illustrating different seat locations and airflow paths');
}
// 3 — Model inputs / exploded architecture layout.
{
  const s=slide(3,layoutNames[2],'A room model built for decisions','Initial scope · one rectangular office and one split AC',`${scope}\nBuilt-in imagegen asset: PitchAssets/room-model-exploded.png. Exploded geometry is conceptual. Future content: screenshots from the actual room editor, with inputs and assumptions retained.`);
  headingBody(s,'geometry','Geometry','Walls, openings and furniture.',72,235,410,28);
  headingBody(s,'occupancy','Occupancy','Seats, people and heat sources.',72,363,410,28);
  headingBody(s,'hvac','HVAC','Placement, airflow and operating settings.',72,491,410,28);
  picture(s,'room-model-exploded',524,214,680,434,'Exploded architectural office model showing geometry, furniture and HVAC inputs');
}
// 4 — End-to-end product proposition / native process template.
{
  const s=slide(4,layoutNames[3],'A clearer way to configure a room','Planned decision workflow',`${scope}\nPresent the user's decision sequence. This is a workflow framework, not evidence that the actions already work. Future content: a reproducible baseline and two candidate runs.`);
  text(s,'workflow-intro','One spatial model. A comparison you can inspect.',72,244,1050,70,32,{color:C.secondary});
  const steps=[['Model','Define the room\nand its assumptions.'],['Simulate','Evaluate energy\nand spatial airflow.'],['Compare','Inspect comfort\nand operating cost.'],['Decide','Choose an option\nwith traceable evidence.']];
  const anchors=[];
  steps.forEach(([title,body],i)=>{
    const x=72+i*289;
    text(s,`workflow-index-${i}`,String(i+1).padStart(2,'0'),x,377,220,35,20,{color:C.teal});
    anchors.push(text(s,`workflow-step-${i}`,title,x,422,224,54,35,{bold:true}));
    text(s,`workflow-detail-${i}`,body,x,495,245,95,24,{color:C.secondary});
  });
  for(let i=0;i<anchors.length-1;i++)connect(s,anchors[i],anchors[i+1]);
}
// 5 — Product workflow / spacious editorial columns.
{
  const s=slide(5,layoutNames[4],'Designed around the room','Mac-first workspace · adaptive iPad and iPhone views planned',`${scope}\nSource: Plans/References/02-architecture.md. Planned Mac workspace, with platform-specific capabilities. iOS does not run external Python or OpenFOAM. No invented application screenshot is used. Future content: replace these workflow columns with real product captures after implementation.`);
  const cols=[['Configure','Room geometry\nEquipment placement\nOperating conditions'],['Inspect','Field views\nSeat-level samples\nQuality checks'],['Compare','Baseline and candidates\nComfort constraints\nEnergy and cost']];
  const anchors=[];
  cols.forEach(([title,body],i)=>{
    const x=72+i*386;
    anchors.push(text(s,`product-step-${i}`,title,x,278,334,65,38,{bold:true}));
    text(s,`product-detail-${i}`,body,x,393,332,165,26,{color:C.secondary});
  });
  connect(s,anchors[0],anchors[1]);connect(s,anchors[1],anchors[2]);
}
// 6 — Physics / native editable method layout.
{
  const s=slide(6,layoutNames[5],'Energy and airflow in one model','Planned linkage · representative day + representative steady-state condition',`${physics}\nThe shared input and boundary conversion are the integration contribution. Capacity, thermal load and electrical power must remain distinct. No performance, speed or accuracy claim is made. Future evidence: engine versions, reproducible input snapshot, valid case and boundary consistency checks.`);
  text(s,'energy-label','01 / ENERGY',72,269,475,36,19,{color:C.teal});
  const a=text(s,'energyplus-name','EnergyPlus',72,322,492,66,44,{bold:true});
  text(s,'energyplus-purpose','Representative-day electricity\nLoads and surface conditions',72,411,486,112,28,{color:C.secondary});
  text(s,'airflow-label','02 / AIRFLOW',688,269,495,36,19,{color:C.teal});
  const b=text(s,'openfoam-name','OpenFOAM',688,322,502,66,44,{bold:true});
  text(s,'openfoam-purpose','Spatial temperature and velocity\nSeat-level evaluation inputs',688,411,510,112,28,{color:C.secondary});
  connect(s,a,b);
  text(s,'shared-boundary','Consistent geometry, loads and HVAC boundaries',72,578,1120,48,29,{bold:true});
}
// 7 — Native comparison table, explicitly pending evidence.
{
  const s=slide(7,layoutNames[6],'One baseline. Two alternatives','Comparison framework · valid numerical results to be added',`${scope}\n${physics}\nThis is an intentionally unpopulated evidence template. All cells explicitly await valid runs; no candidate is ranked. Candidate changes are examples, not tested recommendations. Use identical weather, occupancy, schedules, visual viewpoints and color scales. Tariff requires a sourced rate. Future content: one baseline plus two candidates, electricity in kWh/day, supported seat metrics, cost with currency and tariff source.`);
  text(s,'comparison-condition','Hold the room, weather and occupancy constant.',72,213,1120,46,28,{color:C.secondary});
  nativeTable(s,'candidate-comparison',[
    ['Comparison','Baseline','Direction','Direction\n+ setpoint'],
    ['Changed input','Reference settings','Airflow direction','Direction + setpoint'],
    ['Seat-level comfort','Awaiting valid run','Awaiting valid run','Awaiting valid run'],
    ['Electricity (kWh/day)','Awaiting valid run','Awaiting valid run','Awaiting valid run'],
    ['Operating cost / day','Awaiting tariff + run','Awaiting tariff + run','Awaiting tariff + run'],
  ],[330,268,268,270],269,306,22.5);
}
// 8 — Native quality gates and provenance framework.
{
  const s=slide(8,layoutNames[7],'Evidence before recommendations','Planned quality gates · results must be current and valid',`${physics}\nSource: AGENTS.md; Plans/References/04-data-contracts.md. Task success, quality and freshness are separate states. A completed task alone is not a valid recommendation. Missing or invalid seat samples must not be treated as zero. Future evidence: run ID, immutable snapshot, engine settings, mesh, convergence, conservation, masks and sample validity.`);
  const gates=['Run completed','Quality passed','Inputs current','Samples valid'];
  const anchors=gates.map((name,i)=>{
    const x=72+289*i;
    text(s,`gate-index-${i}`,String(i+1).padStart(2,'0'),x,273,230,34,20,{color:C.teal});
    return text(s,`gate-${i}`,name,x,326,238,94,31,{bold:true});
  });
  for(let i=0;i<anchors.length-1;i++)connect(s,anchors[i],anchors[i+1]);
  [['Input snapshot','Fixed assumptions\nand run identity.'],['Solver record','Versions and mesh\nSolver settings.'],['Quality record','Convergence checks\nValid samples.']].forEach(([title,body],i)=>headingBody(s,`record-${i}`,title,body,72+i*386,493,333,27));
}
// 9 — Value / decision categories, without invented market claims.
{
  const s=slide(9,layoutNames[8],'A practical decision for each room','Proposed value · to be tested in a real office pilot',`${scope}\nThese are planned classes of feasible recommendations. No market size, willingness-to-pay, savings percentage or annual payback is claimed. Future content: user interviews, pilot actions, real quotes and measured outcomes with model applicability documented.`);
  const rows=[['01','Adjust operation','Compare settings before changing equipment.'],['02','Improve comfort','Inspect seat differences and the worst positions.'],['03','Plan a configuration','Assess placement, capacity and cost assumptions.']];
  rows.forEach(([n,title,body],i)=>{
    const x=72+i*386;
    text(s,`value-index-${i}`,n,x,261,300,92,66,{color:C.teal});
    headingBody(s,`value-${i}`,title,body,x,379,332,28);
  });
  text(s,'pilot-value','Start with one office. Validate with real measurements.',72,586,1136,45,29,{bold:true});
}
// 10 — Current maturity / native table with current-state evidence.
{
  const s=slide(10,layoutNames[9],'A working foundation. A defined next step','P0 status · numerical engines are not connected',`Source: README.md; Plans/Delivery/status.md; Plans/Delivery/verification.md. As of 2026-10-02, both app targets, shared navigation, model/task/report boundaries and a Python worker skeleton exist. Current records document Mac and generic iOS Simulator builds; no device or numerical solver success is implied. Concurrent model development is not presented as a completed phase. Future content: verified phase receipts and actual screenshots.` ,48);
  nativeTable(s,'current-progress',[
    ['Layer','Today','Next evidence'],
    ['Native product','Mac + iOS foundation','Room modeling workflow'],
    ['Computation','Interfaces established','Reproducible energy + CFD'],
    ['Decision support','Report boundary defined','Validated comparison + report']
  ],[302,374,460],299,270,25);
}
// 11 — Roadmap / four editable milestone lanes.
{
  const s=slide(11,layoutNames[10],'A focused route to a pilot','Initial timing targets · scope and performance depend on validation',`Source: Plans/References/06-roadmap-and-backlog.md; Plans/Phases/P1-physics-spike.md; Plans/Phases/P5-decision-and-report.md; Plans/Phases/P6-capture-and-calibration.md; Plans/Phases/P7-optimization-and-release.md. Initial competition plan: 48–72 hours, followed by a 6–8 week target. These are planning windows, not commitments or completed milestones. Future content: owner names, verified milestone evidence and a confirmed pilot partner.`);
  const phases=[['P1–P2','Prove physics','Benchmarks\nRoom model'],['P3–P5','Close the loop','Run management\nCompare and report'],['P6','Validate onsite','Measurements\nModel suitability'],['P7','Prepare a pilot','Robust candidates\nDeploy and verify']];
  const anchors=[];
  phases.forEach(([phase,title,body],i)=>{
    const x=72+i*289;
    text(s,`phase-${i}`,phase,x,274,230,34,20,{color:C.teal});
    anchors.push(text(s,`milestone-${i}`,title,x,324,237,88,32,{bold:true}));
    text(s,`milestone-detail-${i}`,body,x,441,242,104,24,{color:C.secondary});
  });
  for(let i=0;i<anchors.length-1;i++)connect(s,anchors[i],anchors[i+1]);
  text(s,'timing-window','48–72 hour competition window / 6–8 week follow-on target',72,581,1136,47,27,{bold:true});
}
// 12 — Closing template; cover asset reused only as a background.
{
  const s=slide(12,layoutNames[11],"Let's validate\none real room",'Concept pitch · October 2026',`${scope}\nClosing invitation proposes a pilot space and measurement access. No existing pilot, customer or commercial partnership is claimed. Built-in imagegen cover asset reused as a background. Future content: confirmed pilot request and contact details.`,64);
  picture(s,'cover-architecture-airflow',0,0,W,H,'Architectural office concept with geometric lines and artistic airflow trajectories','cover');
  s.placeholders.getItem('title').bringToFront();
  text(s,'closing-brand','SimuNow',72,48,300,42,28,{bold:true});
  text(s,'closing-invitation','Seeking a pilot office\nand measurement access.',74,406,424,100,27,{color:C.secondary});
  text(s,'closing-disclosure','Concept illustration · not a simulation result',72,665,1020,25,16,{color:C.muted});
  text(s,'closing-page','12',1166,665,42,24,15,{color:C.muted,align:'right'});
}

const manifest={revision:'v1.1',language:'en',canvas:{width:W,height:H,aspectRatio:'16:9'},font:FONT,palette:C,layouts:layoutNames,slideCount:presentation.slides.items.length,coverHeadline:'Simulate first. Design better.',coverSubtitle:'Airflow and energy in one model. Comfort insights for every seat.',status:'Cover copy refined to express the planned simulation-led decision workflow; editable narrative framework retained. No numerical results.',imageTool:'Built-in imagegen',assets:['cover-architecture-airflow.png','seat-airflow-study.png','room-model-exploded.png']};
await fs.writeFile(path.join(projectRoot,'PitchAssets','style-guide.json'),JSON.stringify(manifest,null,2)+'\n');
const candidatePath=path.join(staging,'candidate.pptx');
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);
await fs.writeFile(path.join(staging,'presentation.json'),JSON.stringify(presentation.toProto()));
await fs.writeFile(path.join(staging,'snapshot.ndjson'),(await presentation.inspect({kind:'slide,textbox,table,image,notes,layout',maxChars:160000})).ndjson);
const renderOnly=process.env.PITCH_RENDER_SLIDES?new Set(process.env.PITCH_RENDER_SLIDES.split(',').map(Number)):null;
for(let i=0;i<presentation.slides.items.length;i++) {
  if(renderOnly&&!renderOnly.has(i+1))continue;
  const s=presentation.slides.items[i];
  const stem=`slide-${String(i+1).padStart(2,'0')}`;
  const png=await presentation.export({slide:s,format:'png',scale:1.25});
  await fs.writeFile(path.join(staging,`${stem}.png`),new Uint8Array(await png.arrayBuffer()));
  const layout=await s.export({format:'layout'});
  await fs.writeFile(path.join(staging,`${stem}.layout.json`),await layout.text());
  console.log(`Rendered ${stem}`);
}
const finalPath=path.join(output,process.env.PITCH_OUTPUT_NAME ?? 'PitchDeck.v1.pptx');
const result=await finalizePresentation({
  workspaceDir,candidatePath,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--cover-role','cover','--validate-bullet-geometry','--validate-heading-fit','--require-native-table-slide','7','--require-native-table-slide','10'],
  explicitTotalSlideCount:12,requiredNativeTableOwnerSlides:[7,10],requiredNativeChartOwnerSlides:[],
  fontPolicy:{basis:'design',families:[FONT]},verifyArtifactToolImport:true,
  receiptPath:path.join(staging,`${path.basename(finalPath)}.validation.json`)
});
console.log(JSON.stringify({finalPath,result}));
