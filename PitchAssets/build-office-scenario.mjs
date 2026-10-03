import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const projectRoot=process.env.PROJECT_ROOT??path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const workspaceDir=process.env.PITCH_WORK_DIR;
const skillDir=process.env.PRESENTATIONS_SKILL_DIR;
const pythonExecutable=process.env.PRESENTATIONS_PYTHON;
if(![workspaceDir,skillDir,pythonExecutable].every(p=>p&&path.isAbsolute(p)))throw new Error('Set absolute task and presentation runtime paths.');
const {resolvePresentationFont,finalizePresentation}=await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const FONT=resolvePresentationFont({fontFamily:'Arial'});
const C={ink:'#20282C',secondary:'#536069',muted:'#64727A',teal:'#277F89',cyan:'#57BCC7',pale:'#F1F4F5',grid:'#D7DFE3',white:'#FFFFFF'};
const build=path.join(workspaceDir,'build');await fs.mkdir(build,{recursive:true});await fs.mkdir(path.join(workspaceDir,'output'),{recursive:true});
const p=Presentation.create({slideSize:{width:1280,height:720}});
p.theme.colorScheme={name:'SimuNow Architectural Light',themeColors:{accent1:C.teal,accent2:C.cyan,accent3:'#788D98',accent4:'#BDC9CE',accent5:'#D6E6E8',accent6:'#6B7880',bg1:C.white,bg2:C.pale,tx1:C.ink,tx2:C.secondary,dk1:C.ink,dk2:C.secondary,lt1:C.white,lt2:C.pale,hlink:C.teal,folHlink:C.secondary}};
const s=p.slides.add();s.background.fill=C.white;
function text(name,value,x,y,width,height,size=24,opts={}){
  const a=s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text=value;a.text.style={typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:opts.align??'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};return a;
}
function table(name,values,x,y,width,heights,columnWidths,fontSizes,firstColumnFill){
  const t=s.tables.add({rows:values.length,columns:values[0].length,left:x,top:y,width,height:heights.reduce((a,b)=>a+b,0),values,columnWidths});
  t.name=name;t.styleOptions={headerRow:false,firstColumn:false,bandedRows:false};
  heights.forEach((h,r)=>{t.rows[r].height=h;});
  for(let r=0;r<values.length;r++)for(let c=0;c<values[r].length;c++){
    const cell=t.getCell(r,c);const header=name==='configuration-inputs'&&r===0;
    cell.fill=header||firstColumnFill&&c===0?C.pale:C.white;
    cell.text.style={typeface:FONT,fontSize:header?17:fontSizes[c],bold:header||c===0,color:header||c===0?C.ink:C.secondary,alignment:'left',verticalAlignment:'middle',autoFit:'none',wrap:'square',insets:{left:10,right:8,top:5,bottom:5}};
  }
  t.cells.block({row:0,column:0,rowCount:values.length,columnCount:values[0].length}).assign({margins:{left:10,right:8,top:5,bottom:5},anchor:'center',borders:{top:{color:C.white,width:0},bottom:{color:C.grid,width:0.7},left:{color:C.white,width:0},right:{color:C.white,width:0}}});
  return t;
}
text('simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
text('slide-title','Office cooling scenario',72,107,1136,68,52,{bold:true});
text('slide-subtitle','Compare AC placement while holding room and operating inputs fixed',72,179,1136,37,25,{color:C.secondary});
text('scenario-section','SCENARIO / ONE OFFICE',72,238,620,31,22,{bold:true,color:C.teal});
text('comparison-section','CONTROLLED COMPARISON',720,238,488,31,22,{bold:true,color:C.teal});
text('room-specification','6 × 4 × 2.8 m room, four occupied seats',72,280,620,35,26,{bold:true});
text('room-invariants','Same furniture, heat loads and weather in both cases',72,319,620,26,18.5,{color:C.secondary});
const imageBytes=new Uint8Array(await fs.readFile(path.join(projectRoot,'PitchAssets/office-scenario-pair.png')));
s.images.add({blob:imageBytes,contentType:'image/png',alt:'Hypothetical paired office configurations with the same window, door and four desks. A has one AC on the side wall; B moves the same unit to the rear wall. Geometry concept only, with no airflow or performance results.',fit:'contain',position:{left:66,top:347,width:638,height:271}});
text('baseline-label','A / SIDE-WALL PLACEMENT',72,623,300,28,18.5,{bold:true,color:C.teal});
text('candidate-label','B / REAR-WALL PLACEMENT',397,623,307,28,18.5,{bold:true,color:C.teal});
text('scenario-question','Which placement balances comfort and electricity?',72,659,1030,31,23,{bold:true});
table('configuration-inputs',[
  ['Parameter','A / Baseline','B / Candidate'],
  ['AC placement','Side wall','Rear wall'],
  ['Setpoint','26 °C','26 °C'],
  ['Supply airflow','0.18 m³/s','0.18 m³/s'],
  ['Operating period','09:00–17:00','09:00–17:00'],
],720,280,488,[34,34,34,34,34],[202,143,143],[17.5,17.5,17.5],false);
text('scenario-input-caption','Illustrative inputs. AC placement is the intended change.',720,459,488,24,14.5,{color:C.muted});
text('evidence-heading','EVALUATION / RESULTS PENDING',720,486,488,28,20,{bold:true,color:C.teal});
table('scenario-evaluation',[
  ['Seat comfort','Temperature, radiation, air speed\nHumidity, clothing, activity [6]'],
  ['Electricity','Representative-day kWh'],
  ['Operating cost','Daily kWh × sourced tariff'],
],720,520,488,[56,39,39],[150,338],[17,16.5],true);
text('scenario-page-number','05',1166,665,42,24,15,{color:C.muted,align:'right'});
text('scenario-footer','[4,6] Proposed evaluation. Geometry and input values are hypothetical. Complete inputs and valid runs are required before comparing results.',72,695,1120,20,12.5,{color:C.muted});
s.speakerNotes.textFrame.setText(`Purpose: follow Introducing SimuNow with a concrete office configuration comparison. This page is a planned application scenario, not a live product screenshot, a measured office, or a computed result.\n\nInternal hypothetical inputs: 6 by 4 by 2.8 metre room, four occupied seats, 26 °C thermostat setpoint, 0.18 m³/s supply airflow and 09:00–17:00 operation. These are illustrative design assumptions chosen for the scenario. They are not measured data, recommended universal settings, a calibrated benchmark or complete solver input. Setpoint is distinct from supply-air temperature; supply airflow is distinct from air speed, cooling capacity and electrical input.\n\nA is the side-wall baseline; B moves one identical AC unit to the rear wall. The illustration preserves the same room, desks, chairs, window and door. Room construction, weather, solar inputs, people/equipment loads, schedule, device performance and other physical inputs should be shared between cases. Placement is the intended changed configuration variable; supply direction relative to the unit and geometry must be documented so incidental differences are not misattributed. All geometries and positions must be defined in the actual model before running an evaluation. The picture is not a dimensioned model.\n\nProposed comparison: evaluate thermal conditions separately at each occupied seat, representative-day electricity in kWh/day and operating cost using sourced tariffs with matched currency/billing assumptions. No computed values, preferred candidate, savings, measured satisfaction or Standard 55 compliance are shown. A steady field cannot establish cooldown time and a representative day cannot establish annual savings. Evidence requires complete inputs, successful quality-passed current runs and valid samples as described by source [4].\n\n[4] SimuNow (2026). AGENTS.md user-approved product-vision snapshot, SHA-256 16e3fd5e2a75c14cb6e7abe5398f4422e370a9bd34879836ebab760fd28d74b4. Physical and result constraints; Data and task conventions. This page extends the previously approved pitch vision and does not modify the current local-development roadmap or claim numerical engines are connected.\n\n[6] ASHRAE (2023). ANSI/ASHRAE Standard 55-2023, Thermal Environmental Conditions for Human Occupancy. Official public overview: https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy . Accessed 3 October 2026. Supports the combination of temperature, thermal radiation, humidity and air speed with clothing and activity as thermal-comfort inputs. It does not establish scenario performance or compliance.\n\nImage provenance: PitchAssets/office-scenario-pair.png, generated by the built-in imagegen tool on 3 October 2026. Exact prompt: PitchAssets/office-scenario-imagegen-prompt.json. Two matched geometric concepts, no computed flow field or thermal outcome. Scenario assumptions and sources: PitchAssets/office-scenario-source.json. Both tables and all labels/disclosures are native editable PowerPoint objects.`);
const patch=path.join(build,'office-scenario-page.pptx');await(await PresentationFile.exportPptx(p)).save(patch);
const png=await p.export({slide:s,format:'png',scale:1.25});await fs.writeFile(path.join(build,'office-scenario-page.png'),new Uint8Array(await png.arrayBuffer()));
const original=process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx');const candidate=path.join(build,'candidate.pptx');
const merged=spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets/replace-office-scenario-slide.py'),original,patch,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);console.log(merged.stdout.trim());
const finalPath=path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.office-scenario.pptx');
const result=await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-heading-fit','--require-native-table-slide','3','--require-native-table-slide','5','--require-native-table-slide','8','--require-native-table-slide','11'],
  explicitTotalSlideCount:14,requiredNativeTableOwnerSlides:[3,5,8,11],requiredNativeChartOwnerSlides:[2],
  fontPolicy:{basis:'reference',families:[FONT],referencePath:original,referenceSha256:createHash('sha256').update(await fs.readFile(original)).digest('hex')},verifyArtifactToolImport:true,
  receiptPath:path.join(build,`${path.basename(finalPath)}.validation.json`)
});
console.log(JSON.stringify({finalPath,result}));
