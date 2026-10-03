import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

// Author only the two changed pages, then preserve the current deck package.
const projectRoot = process.env.PROJECT_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceDir = process.env.PITCH_WORK_DIR;
const skillDir = process.env.PRESENTATIONS_SKILL_DIR;
const pythonExecutable = process.env.PRESENTATIONS_PYTHON;
if (![workspaceDir,skillDir,pythonExecutable].every(p=>p&&path.isAbsolute(p))) {
  throw new Error('Set PITCH_WORK_DIR, PRESENTATIONS_SKILL_DIR and PRESENTATIONS_PYTHON to absolute runtime paths.');
}
const { resolvePresentationFont, finalizePresentation } = await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const FONT = resolvePresentationFont({fontFamily:'Arial'});
const C = {ink:'#20282C',secondary:'#536069',muted:'#64727A',teal:'#277F89',cyan:'#57BCC7',grid:'#D7DFE3',pale:'#F1F4F5',white:'#FFFFFF'};
const build = path.join(workspaceDir,'build');
await fs.mkdir(build,{recursive:true});
await fs.mkdir(path.join(workspaceDir,'output'),{recursive:true});
const evidence = JSON.parse(await fs.readFile(path.join(projectRoot,'PitchAssets','research-sources.json'),'utf8'));
const p = Presentation.create({slideSize:{width:1280,height:720}});
p.theme.colorScheme = {name:'SimuNow Architectural Light',themeColors:{accent1:C.teal,accent2:C.cyan,accent3:'#788D98',accent4:'#BDC9CE',accent5:'#D6E6E8',accent6:'#6B7880',bg1:C.white,bg2:C.pale,tx1:C.ink,tx2:C.secondary,dk1:C.ink,dk2:C.secondary,lt1:C.white,lt2:C.pale,hlink:C.teal,folHlink:C.secondary}};
function text(s,name,value,x,y,width,height,size=24,opts={}) {
  const a = s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text = value;
  a.text.style = {typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:opts.align??'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};
  return a;
}
function slide(title,number,subtitle) {
  const s = p.slides.add();
  s.background.fill = C.white;
  text(s,'simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
  text(s,'slide-title',title,72,107,1136,68,52,{bold:true});
  text(s,'slide-subtitle',subtitle,72,179,1136,37,25,{color:C.secondary});
  text(s,`decision-page-${number}`,String(number).padStart(2,'0'),1166,665,42,24,15,{color:C.muted,align:'right'});
  return s;
}

{
  const s = slide('Room-level cooling decisions',3,'AC placement and operating settings affect both electricity use and local comfort');
  text(s,'room-section','CONFIGURATION  /  ONE OFFICE',72,238,514,31,22,{bold:true,color:C.teal});
  text(s,'evidence-section','EVIDENCE  /  THREE DECISION LEVELS',630,238,578,31,22,{bold:true,color:C.teal});
  const blob = new Uint8Array(await fs.readFile(path.join(projectRoot,'PitchAssets','room-decision-office.png')));
  s.images.add({blob,contentType:'image/png',alt:'Concept office with window, four desks and a wall-mounted split air conditioner. Geometry only, not simulation output.',fit:'contain',position:{left:66,top:275,width:536,height:234}});
  text(s,'room-caption','Window, furniture and occupied positions · concept illustration',72,512,520,21,14,{color:C.muted});
  text(s,'control-section','WHAT OPERATORS CAN ADJUST',72,540,520,23,16,{bold:true,color:C.teal});
  const variables = [['Placement','m'],['Direction','°'],['Airflow rate','m³/s'],['Setpoint','°C']];
  variables.forEach(([label,unit],i)=>{
    const x = 72+i*130;
    text(s,`variable-${i}-label`,label,x,565,125,23,18,{bold:true});
    text(s,`variable-${i}-unit`,unit,x,588,125,22,17,{color:C.secondary});
  });
  const values = [
    ['01 / ENERGY\nkWh per day','Weather, solar + internal gains [7]\nSchedule + equipment efficiency\nRepresentative-day evaluation [4]'],
    ['02 / COMFORT\nAt each seat','Air + mean radiant temperature;\nair speed + humidity + clothing;\nactivity; local evaluation [6]'],
    ['03 / CHOICE\nBaseline vs options','Same room, weather and occupancy\nEnergy + comfort constraints [3,4]\nCompare valid, current results'],
  ];
  const table = s.tables.add({rows:3,columns:2,left:630,top:280,width:578,height:309,values,columnWidths:[183,395]});
  table.styleOptions = {headerRow:false,firstColumn:true,bandedRows:false};
  [103,103,103].forEach((h,i)=>{table.rows[i].height=h;});
  for(let r=0;r<3;r++)for(let c=0;c<2;c++){
    const cell = table.getCell(r,c);
    cell.fill = c===0?C.pale:C.white;
    cell.text.style = {typeface:FONT,fontSize:c===0?19:18.5,bold:c===0,color:c===0?C.ink:C.secondary,alignment:'left',verticalAlignment:'middle',autoFit:'none',wrap:'square',insets:{left:14,right:12,top:12,bottom:12}};
  }
  table.cells.block({row:0,column:0,rowCount:3,columnCount:2}).assign({margins:{left:14,right:12,top:12,bottom:12},anchor:'center',borders:{top:{color:C.white,width:0},bottom:{color:C.grid,width:0.7},left:{color:C.white,width:0},right:{color:C.white,width:0}}});
  text(s,'room-research-question','Which AC placement and settings can reduce electricity use\nwhile maintaining comfort at occupied seats?',72,619,1060,58,24,{bold:true});
  text(s,'room-citations','[6] ASHRAE Standard 55-2023, official overview. [7] EnergyPlus Engineering Reference, “Zone Internal Gains”.\n[3,4] SimuNow scope and methodology. Proposed evaluation framework; no savings or computed comfort results are shown.',72,679,1080,29,12.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`Purpose: translate the macro electricity problem on slide 2 into a bounded room-level decision, before the room-model architecture on slide 4. This is a proposed evaluation framework, not an implemented or validated optimization result.\n\nAdjustable variables: indoor-unit placement is a position in metres; direction is an orientation in degrees; airflow is volumetric flow in m³/s; setpoint is the thermostat setting in °C. Setpoint is not supply-air temperature. Equipment cooling capacity, electric input power and supply temperature require separate model inputs.\n\nRoom electricity is a representative-day quantity in kWh/day. Its weather, solar, internal loads, operating schedule and HVAC performance must be stated. A day is not an annual energy or savings estimate.\n\nSeat comfort requires local air temperature, a radiant-temperature basis, air speed and humidity, with stated clothing and activity. Local draft and other discomfort checks require appropriate model coverage and valid samples. The six basic thermal-comfort factors are cited to [6]; this page does not claim Standard 55 compliance, measured satisfaction, or that every local-discomfort criterion is implemented.\n\nThe energy run and representative steady-state airflow/comfort condition are distinct evaluation scopes. Compare baseline and candidates with the same room geometry except the intended configuration change, weather, occupancy, loads and evaluation period. Use only successful, quality-passed, current runs with valid seat samples. Do not infer cooldown time from a steady field. See [3,4] project sources.\n\n[6] ASHRAE (2023). ANSI/ASHRAE Standard 55-2023, Thermal Environmental Conditions for Human Occupancy. Official public overview: https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy . Supports the factors temperature, thermal radiation, humidity and air speed, together with activity and clothing. The standard overview also describes local discomfort from vertical gradients. Accessed 3 October 2026.\n\n[7] EnergyPlus (n.d.). Engineering Reference, Zone Internal Gains, Sources and Types of Gains. https://energyplus.readthedocs.io/en/latest/guides/engineering-reference/17.1-zone-internal-gains.html . Supports inclusion of people, lights and equipment in the zone heat balance, and separation of convective, radiant and latent gains. Accessed 3 October 2026. This citation does not establish a savings percentage or a universal relation between placement and electrical efficiency.\n\n[3] Plans/References/01-product-scope.md and 03-experience-design.md. [4] Plans/References/02-architecture.md, 04-data-contracts.md, 05-computation-and-decision.md and AGENTS.md.\n\nRoom art generated with the built-in imagegen tool on 3 October 2026. Asset: PitchAssets/room-decision-office.png; full prompt: PitchAssets/room-decision-imagegen-prompt.json. The illustration contains no computed flow or temperature field. All text and the evaluation matrix are native editable PowerPoint objects.`);
}

{
  const s = slide('References',14,'Statistical sources, technical basis, project evidence and illustration provenance');
  const L=72,R=688,W=520;
  text(s,'ref1-title','[1] EMSD (2026)',L,238,W,31,23,{bold:true});
  text(s,'ref1-body','Hong Kong Energy End-use Data 2026\n2024 statistics. Tables 12 and 39, pp. 27 and 54.\nCategory definition: revision 21, p. 78.',L,276,W,71,18.5,{color:C.secondary});
  text(s,'ref1-link','EMSD official report (PDF)',L,351,W,27,18.5,{color:C.teal});
  text(s,'ref2-title','[2] International Energy Agency (2026)',L,394,W,31,23,{bold:true});
  text(s,'ref2-body','Cooling a hotter world: El Niño meets strong\ngrowth in global electricity demand\nCommentary, 10 July 2026. Licence: CC BY 4.0.',L,432,W,71,18.5,{color:C.secondary});
  text(s,'ref2-link','IEA official commentary',L,507,W,27,18.5,{color:C.teal});
  text(s,'ref6-title','[6] ASHRAE (2023)',L,548,W,31,23,{bold:true});
  text(s,'ref6-body','ANSI/ASHRAE Standard 55-2023\nThermal Environmental Conditions for Human Occupancy',L,586,W,46,18,{color:C.secondary});
  text(s,'ref6-link','Standard 55 official overview',L,638,W,27,18.5,{color:C.teal});

  text(s,'ref7-title','[7] EnergyPlus Engineering Reference',R,238,W,31,23,{bold:true});
  text(s,'ref7-body','Zone Internal Gains · Sources and Types of Gains\nPeople, lights and equipment in the heat balance.\nConvective, radiant and latent components.',R,276,W,71,18.5,{color:C.secondary});
  text(s,'ref7-link','EnergyPlus official documentation',R,351,W,27,18.5,{color:C.teal});
  text(s,'project-ref-section','INTERNAL PROJECT SOURCES [3–5]',R,394,W,28,20,{bold:true,color:C.teal});
  text(s,'ref3-title','[3] Product and experience',R,432,W,27,20,{bold:true});
  text(s,'ref3-body','Plans/References/01-product-scope.md\nPlans/References/03-experience-design.md',R,463,W,43,17.5,{color:C.secondary});
  text(s,'ref4-title','[4] Architecture, contracts and physics',R,519,W,27,20,{bold:true});
  text(s,'ref4-body','Plans/References/02-architecture.md; 04-data-contracts.md\nPlans/References/05-computation-and-decision.md; AGENTS.md',R,550,W,43,17,{color:C.secondary});
  text(s,'ref5-title','[5] Delivery evidence and roadmap',R,606,W,27,20,{bold:true});
  text(s,'ref5-body','README; Plans/Delivery/status.md and verification.md\nRoadmap/backlog; phase work packages P1/P5/P6/P7',R,637,W,43,16.5,{color:C.secondary});
  text(s,'reference-disclosure','Web sources accessed 3 Oct 2026. Full citations and project paths are in speaker notes. Planned capabilities are identified as such.\nConcept illustrations: built-in imagegen, 2–3 Oct 2026. Assets and prompts in PitchAssets/. No artwork is simulation evidence.',72,684,1080,32,12.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`References for the presentation.\n\n[1] Electrical and Mechanical Services Department, Government of the Hong Kong Special Administrative Region (2026). Hong Kong Energy End-use Data 2026. Tables 12 and 39, printed pp. 27 and 54. Chronology of Major Revisions item 21, printed p. 78. ${evidence.sources[0].url}\n[2] International Energy Agency (2026). Cooling a hotter world: El Niño meets strong growth in global electricity demand. IEA, Paris. Commentary, 10 July 2026. Licence: CC BY 4.0. ${evidence.sources[1].url}\n[3] SimuNow (2026). Plans/References/01-product-scope.md and Plans/References/03-experience-design.md. Internal scope and experience sources for slides 1, 3–6, 8, 10 and 13.\n[4] SimuNow (2026). Plans/References/02-architecture.md, Plans/References/04-data-contracts.md, Plans/References/05-computation-and-decision.md and AGENTS.md. Internal methodology and evidence constraints for slides 3, 4 and 6–9.\n[5] SimuNow (2026). README.md; Plans/Delivery/status.md; Plans/Delivery/verification.md; Plans/References/06-roadmap-and-backlog.md; Plans/Phases/P1-physics-spike.md, P5-decision-and-report.md, P6-capture-and-calibration.md and P7-optimization-and-release.md. Internal maturity and milestones for slides 11–12.\n[6] ASHRAE (2023). ANSI/ASHRAE Standard 55-2023, Thermal Environmental Conditions for Human Occupancy. Official public overview: https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy . Supports the basic environmental and personal comfort factors on slide 3. No claim of Standard 55 compliance is made.\n[7] EnergyPlus (n.d.). Engineering Reference, Zone Internal Gains, Sources and Types of Gains. https://energyplus.readthedocs.io/en/latest/guides/engineering-reference/17.1-zone-internal-gains.html . Supports internal loads and the separation of convective, radiant and latent gains on slide 3.\n\nIllustration provenance: cover-architecture-airflow.png, seat-airflow-study.png and room-model-exploded.png generated by the built-in imagegen tool on 2 October 2026. problem-hong-kong-office.png and room-decision-office.png generated on 3 October 2026. Prompt files: PitchAssets/imagegen-prompts.json, problem-imagegen-prompt.json and room-decision-imagegen-prompt.json. Artwork is concept material, not measured or simulated performance.\n\nExternal sources accessed 3 October 2026. Internal paths are relative to the SimuNow project root. Shortened visible project names on this page expand to the full paths in this note. Numerical and comfort functionality is planned unless a delivery source explicitly establishes implemented behavior.`);
}

const additions = path.join(build,'room-decision-pages.pptx');
await (await PresentationFile.exportPptx(p)).save(additions);
for(let i=0;i<p.slides.items.length;i++) {
  const png=await p.export({slide:p.slides.items[i],format:'png',scale:1.25});
  await fs.writeFile(path.join(build,`room-page-${i+1}.png`),new Uint8Array(await png.arrayBuffer()));
}
const original = process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx');
const candidate = path.join(build,'candidate.pptx');
const merged=spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets','replace-room-decision-slides.py'),original,additions,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);
console.log(merged.stdout.trim());
const finalPath = path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.room-decisions.pptx');
const result=await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-heading-fit','--require-native-table-slide','3','--require-native-table-slide','8','--require-native-table-slide','11'],
  explicitTotalSlideCount:14,requiredNativeTableOwnerSlides:[3,8,11],requiredNativeChartOwnerSlides:[2],
  fontPolicy:{basis:'reference',families:[FONT],referencePath:original,referenceSha256:createHash('sha256').update(await fs.readFile(original)).digest('hex')},
  verifyArtifactToolImport:true,
  receiptPath:path.join(build,`${path.basename(finalPath)}.validation.json`)
});
console.log(JSON.stringify({finalPath,result}));
