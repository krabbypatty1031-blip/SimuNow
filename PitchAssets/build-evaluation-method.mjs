import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const projectRoot=process.env.PROJECT_ROOT??path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const workspaceDir=process.env.PITCH_WORK_DIR,skillDir=process.env.PRESENTATIONS_SKILL_DIR,pythonExecutable=process.env.PRESENTATIONS_PYTHON;
if(![workspaceDir,skillDir,pythonExecutable].every(p=>p&&path.isAbsolute(p)))throw new Error('Set absolute presentation runtime and task paths.');
const {resolvePresentationFont,finalizePresentation}=await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const FONT=resolvePresentationFont({fontFamily:'Arial'});
const C={ink:'#20282C',secondary:'#536069',muted:'#64727A',teal:'#277F89',cyan:'#57BCC7',pale:'#F1F4F5',ice:'#EAF4F5',grid:'#D7DFE3',white:'#FFFFFF'};
const build=path.join(workspaceDir,'build');await fs.mkdir(build,{recursive:true});await fs.mkdir(path.join(workspaceDir,'output'),{recursive:true});
const p=Presentation.create({slideSize:{width:1280,height:720}});
p.theme.colorScheme={name:'SimuNow Architectural Light',themeColors:{accent1:C.teal,accent2:C.cyan,accent3:'#788D98',accent4:'#BDC9CE',accent5:'#D6E6E8',accent6:'#6B7880',bg1:C.white,bg2:C.pale,tx1:C.ink,tx2:C.secondary,dk1:C.ink,dk2:C.secondary,lt1:C.white,lt2:C.pale,hlink:C.teal,folHlink:C.secondary}};
function text(s,name,value,x,y,width,height,size=24,opts={}){
  const a=s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text=value;a.text.style={typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:opts.align??'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};return a;
}
function page(title,subtitle,number){
  const s=p.slides.add();s.background.fill=C.white;
  text(s,'simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
  text(s,'slide-title',title,72,107,1136,68,52,{bold:true});
  text(s,'slide-subtitle',subtitle,72,179,1136,37,25,{color:C.secondary});
  text(s,'page-number',String(number).padStart(2,'0'),1166,665,42,24,15,{color:C.muted,align:'right'});return s;
}
function node(s,name,x,y,width,height,fill=C.white){return s.shapes.add({geometry:'rect',name,position:{left:x,top:y,width,height},fill,line:{fill:C.grid,width:1}});}
function connect(s,source,target){return s.shapes.connect(source,target,{kind:'elbow',fromSide:'right',toSide:'left',line:{fill:C.teal,width:1.5},tail:{type:'triangle',width:'sm',length:'sm'}});}

{
  const s=page('Evaluation method','Planned workflow for comparing baseline and candidate room configurations',6);
  text(s,'inputs-heading','01 / SHARED INPUTS',72,238,294,31,22,{bold:true,color:C.teal});
  text(s,'analysis-heading','02 / ANALYSIS SCOPES',428,238,362,31,22,{bold:true,color:C.teal});
  text(s,'decision-heading','03 / DECISION EVIDENCE',854,238,354,31,22,{bold:true,color:C.teal});
  const input=node(s,'shared-room-inputs',72,280,294,288);
  const energy=node(s,'planned-energy-analysis',428,280,362,130,C.ice);
  const airflow=node(s,'planned-spatial-analysis',428,438,362,130,C.ice);
  const decision=node(s,'decision-evidence',854,280,354,288,C.pale);
  const imageBytes=new Uint8Array(await fs.readFile(path.join(projectRoot,'PitchAssets/method-seat-sampling.png')));
  s.images.add({blob:imageBytes,contentType:'image/png',alt:'Office geometry concept with four desks, four chairs and four teal points at occupied-seat locations. Points indicate proposed sampling only; no flow or temperature field is shown.',fit:'contain',position:{left:80,top:292,width:278,height:163}});
  text(s,'sampling-caption','Occupied-seat samples (concept)',86,466,266,23,14.5,{color:C.muted});
  text(s,'common-input-list','Geometry + envelope\nWeather + internal loads\nAC settings + schedule',86,495,266,70,18.5,{color:C.secondary});
  text(s,'energy-engine','EnergyPlus [7,8]',442,291,334,31,24,{bold:true});
  text(s,'energy-scope','Representative day',442,329,334,25,18.5,{bold:true,color:C.teal});
  text(s,'energy-output','AC electricity (kWh/day)',442,358,334,26,19,{color:C.secondary});
  text(s,'energy-scope-limit','Annual savings need an annual basis',442,388,334,22,15.5,{color:C.muted});
  text(s,'airflow-engine','OpenFOAM [9]',442,449,334,31,24,{bold:true});
  text(s,'airflow-scope','Representative steady state',442,487,334,25,18.5,{bold:true,color:C.teal});
  text(s,'airflow-output','Air temperature (°C) + air speed (m/s)',442,516,334,25,17.5,{color:C.secondary});
  text(s,'airflow-scope-limit','Cooldown time needs transient analysis',442,545,334,22,15.5,{color:C.muted});
  text(s,'comfort-heading','Position-level comfort [6]',868,293,326,29,20.5,{bold:true,color:C.teal});
  text(s,'comfort-required-inputs','Air + mean radiant temperature\nAir speed + humidity\nClothing + activity',868,328,326,67,18,{color:C.secondary});
  text(s,'daily-energy-heading','Daily AC electricity',868,410,326,27,20.5,{bold:true,color:C.teal});
  text(s,'daily-energy-detail','Representative-day kWh',868,440,326,26,18,{color:C.secondary});
  text(s,'cost-heading','Operating cost',868,488,326,27,20.5,{bold:true,color:C.teal});
  text(s,'cost-detail','Valid kWh + sourced tariff',868,519,326,26,18,{color:C.secondary});
  connect(s,input,energy);connect(s,input,airflow);connect(s,energy,decision);connect(s,airflow,decision);
  text(s,'quality-heading','EVIDENCE BEFORE COMPARISON [4]',72,594,1136,29,20.5,{bold:true,color:C.teal});
  const checks=[['Inputs complete','Snapshot + run ID'],['Quality passed','Convergence + balance'],['Results current','Same input hash'],['Seat samples valid','Outside solid geometry']];
  checks.forEach(([label,detail],i)=>{
    const x=72+i*284;text(s,`check-${i}-label`,label,x,630,254,28,19,{bold:true});text(s,`check-${i}-detail`,detail,x,660,254,24,15.5,{color:C.secondary});
  });
  text(s,'method-disclosure','[4,6–9] Planned method. No computed fields or outcome claims. Scope and quality checks are required for comparison.',72,695,1120,20,12.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`Purpose: explain the proposed evaluation basis after the office scenario. This is the user-approved EnergyPlus/OpenFOAM pitch vision, not a claim that the numerical pipeline is implemented, coupled or physically validated.\n\nShared inputs: room and construction geometry, furniture, occupied positions, weather and solar inputs, people/equipment heat loads, schedules and HVAC performance. Physical fields must distinguish thermostat setpoint, supply-air temperature, cooling capacity, electrical input, volumetric supply airflow and velocity, with units. Input snapshots and coordinate/geometry transformations need consistent identities and units across analyses.\n\nEnergy scope: a representative-day EnergyPlus run provides the planned AC electricity quantity in kWh/day, using an explicitly defined AC/device meter scope rather than assuming that a whole-building meter is AC-only. Real equipment performance and operating schedules are needed. Thermal load alone does not establish electrical consumption, and an ideal-load model is not sufficient evidence of actual device electricity. The representative-day choice is a SimuNow evaluation scope; it is not an annual savings result. [7] supports internal gains, and [8] supports energy/load simulation, model/weather inputs, and output variables/meters.\n\nSpatial scope: planned OpenFOAM analysis under a selected representative steady condition provides local air temperature and velocity. Thermal boundary conditions, heat-source consistency, mesh, physical models and solver settings must be documented and quality-checked. [9] is official documentation for an example steady heat-transfer solver with temperature and velocity fields; it is not a selected or tested SimuNow runtime configuration. A steady field does not establish startup cooling time. Links in the diagram show intended information relationships, not an implemented transient or two-way coupling. A placement change does not automatically establish an electricity reduction without a validated method connecting the relevant physics.\n\nComfort: evaluate occupied positions only when local air temperature, a mean-radiant-temperature basis, velocity, humidity, clothing and activity are available and the comfort model applies. Additional local-discomfort and sampling-height coverage may be required. [6] supports the basic environmental and personal factors. The page does not claim Standard 55 compliance, measured satisfaction, calibrated confidence, a PMV/PPD result or full comfort coverage.\n\nDecision evidence: compare matched representative-day electricity and separately scoped local comfort; operating cost additionally requires a sourced tariff and matched currency/billing assumptions. A flat energy rate is only one possible tariff basis; no prices or costs are invented. Quality before comparison includes complete inputs, immutable snapshot/run identity, successful runs with convergence/conservation evidence where applicable, current input hashes, and valid seat samples outside solid geometry. A completed task is not equivalent to quality passed or inputs current. These are planned numerical-evidence requirements from [4].\n\n[4] SimuNow (2026), AGENTS.md user-approved product-vision snapshot. SHA-256 16e3fd5e2a75c14cb6e7abe5398f4422e370a9bd34879836ebab760fd28d74b4. Physical and result constraints; Data and task conventions. Current local-development roadmap and implementation status remain separate from this proposed numerical evaluation.\n[6] ASHRAE (2023), ANSI/ASHRAE Standard 55-2023 official public overview. https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy . Environmental and personal comfort factors.\n[7] EnergyPlus Engineering Reference, Zone Internal Gains, Sources and Types of Gains. https://energyplus.readthedocs.io/en/latest/guides/engineering-reference/17.1-zone-internal-gains.html .\n[8] EnergyPlus, Quick Start Guide, online 26.2 documentation as accessed. Sections What is EnergyPlus?, Running EnergyPlus and Adding an output variable. https://energyplus.readthedocs.io/en/stable/quick_start/quick_start.html . Supports geometry/construction/use/system inputs, energy/load analysis, weather input and variables/meters. Documentation version does not select a SimuNow runtime version.\n[9] OpenCFD Ltd., OpenFOAM v2306 documentation, buoyantSimpleFoam. Overview and Input requirements. https://doc.openfoam.com/2306/tools/processing/solvers/rtm/heat-transfer/buoyantSimpleFoam/ . Describes an example steady-state heat-transfer solver with U [m/s] and T [K]; presentation temperature display may convert K to °C. The solver is not fixed or validated for SimuNow.\nExternal sources accessed 3 October 2026. No source establishes SimuNow numerical performance or outcome accuracy.\n\nIllustration: PitchAssets/method-seat-sampling.png, built-in imagegen, 3 October 2026. Full prompt: PitchAssets/method-imagegen-prompt.json. Four teal points are hypothetical occupied-seat sample markers, not physical particles or results. Geometry is not a dimensioned model. Sources and boundaries: PitchAssets/method-sources.json.`);
}

{
  const s=page('References','Statistical sources, technical basis, project evidence and illustration provenance',14);
  const L=72,M=468,R=864,W=344;
  const entry=(id,title,body,x,y,link,linkY)=>{
    text(s,`ref${id}-title`,`[${id}] ${title}`,x,y,W,30,22,{bold:true});
    text(s,`ref${id}-body`,body,x,y+38,W,72,17.5,{color:C.secondary});
    if(link)text(s,`ref${id}-link`,link,x,linkY,W,26,17,{color:C.teal});
  };
  entry(1,'EMSD (2026)','Hong Kong Energy End-use Data 2026\n2024 statistics. Tables 12 and 39\npp. 27 and 54. Definition: p. 78.',L,238,'EMSD official report (PDF)',351);
  entry(2,'IEA (2026)','Cooling a hotter world: El Niño meets\nstrong growth in electricity demand\n10 July 2026. CC BY 4.0.',L,398,'IEA official commentary',511);
  entry(6,'ASHRAE (2023)','ANSI/ASHRAE Standard 55-2023\nThermal Environmental Conditions\nfor Human Occupancy',L,548,'Standard 55 official overview',662);
  entry(7,'EnergyPlus Engineering Ref.','Engineering Reference\nZone Internal Gains\nPeople, lights, equipment and loads',M,238,'EnergyPlus official documentation',351);
  entry(8,'EnergyPlus Quick Start','Online documentation (26.2)\nBuilding + weather model inputs\nOutput variables and meters',M,398,'EnergyPlus official guide',511);
  entry(9,'OpenCFD (v2306 docs)','OpenFOAM: buoyantSimpleFoam\nSteady heat transfer\nTemperature and velocity fields',M,548,'OpenFOAM official documentation',662);
  text(s,'internal-reference-heading','[3–5] INTERNAL SOURCES',R,238,W,30,20.5,{bold:true,color:C.teal});
  entry(3,'Product and experience','Product scope and experience design\nPlans/References/01 and 03',R,280);
  entry(4,'Architecture and physics','Architecture, contracts and physics\nPlans/References/02, 04 and 05\nAGENTS.md approved vision snapshot',R,398);
  entry(5,'Delivery and roadmap','README and delivery evidence\nPlans/Delivery: status, verification\nRoadmap and phase work packages',R,548);
  text(s,'reference-disclosure','Accessed 3 Oct 2026. Full citations in notes. Concept illustrations: built-in imagegen. Assets and prompts in PitchAssets/.',72,695,1120,20,12.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`Additional sources for slide 6. Existing citations and illustration provenance in these notes remain applicable.\n\n[8] EnergyPlus, Quick Start Guide, online 26.2 documentation as accessed 3 October 2026. Sections What is EnergyPlus?, Running EnergyPlus and Adding an output variable. https://energyplus.readthedocs.io/en/stable/quick_start/quick_start.html . Supports energy/load analysis, building-system and weather inputs, output variables/meters. This documentation version is a citation, not a selected SimuNow runtime.\n\n[9] OpenCFD Ltd., OpenFOAM v2306 documentation, buoyantSimpleFoam. Overview and Input requirements. https://doc.openfoam.com/2306/tools/processing/solvers/rtm/heat-transfer/buoyantSimpleFoam/ . Example steady-state heat-transfer solver with temperature T [K] and velocity U [m/s]. Accessed 3 October 2026 via official indexed documentation. This citation does not select, validate or integrate that solver into SimuNow.\n\nSlide 6 reuses [4] the user-approved AGENTS.md product-vision snapshot, [6] ASHRAE environmental/personal factors, and [7] EnergyPlus internal gains. All diagram links and evaluation scopes describe a planned method. Current local-development implementation and this numerical product vision are separate. No computed field, savings, comfort, compliance, satisfaction or cost result is claimed.\n\nAdditional illustration: PitchAssets/method-seat-sampling.png, built-in imagegen, 3 October 2026. Full prompt in PitchAssets/method-imagegen-prompt.json. Hypothetical geometry and sampling markers only, not numerical evidence.\n\nExpanded internal locators: [3] Plans/References/01-product-scope.md and 03-experience-design.md. [4] Plans/References/02-architecture.md, 04-data-contracts.md, 05-computation-and-decision.md and the approved AGENTS.md snapshot hash shown on slide 4. [5] README.md, Plans/Delivery/status.md, verification.md, Plans/References/06-roadmap-and-backlog.md and the previously cited historical P1/P5/P6/P7 phase packages. Short visible locators on the page expand to these paths.`);
}

const additions=path.join(build,'evaluation-method-pages.pptx');await(await PresentationFile.exportPptx(p)).save(additions);
for(let i=0;i<p.slides.items.length;i++){const png=await p.export({slide:p.slides.items[i],format:'png',scale:1.25});await fs.writeFile(path.join(build,`method-page-${i+1}.png`),new Uint8Array(await png.arrayBuffer()));}
const original=process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx'),candidate=path.join(build,'candidate.pptx');
const merged=spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets/replace-evaluation-method-slides.py'),original,additions,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);console.log(merged.stdout.trim());
const finalPath=path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.evaluation-method.pptx');
const result=await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-heading-fit','--require-native-table-slide','3','--require-native-table-slide','5','--require-native-table-slide','8','--require-native-table-slide','11'],
  explicitTotalSlideCount:14,requiredNativeTableOwnerSlides:[3,5,8,11],requiredNativeChartOwnerSlides:[2],
  fontPolicy:{basis:'reference',families:[FONT],referencePath:original,referenceSha256:createHash('sha256').update(await fs.readFile(original)).digest('hex')},verifyArtifactToolImport:true,
  receiptPath:path.join(build,`${path.basename(finalPath)}.validation.json`)
});console.log(JSON.stringify({finalPath,result}));
