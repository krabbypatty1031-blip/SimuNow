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
if(![workspaceDir,skillDir,pythonExecutable].every(p=>p&&path.isAbsolute(p)))throw new Error('Set the absolute presentation runtime and task paths.');
const {resolvePresentationFont,finalizePresentation}=await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const FONT=resolvePresentationFont({fontFamily:'Arial'});
const C={ink:'#20282C',secondary:'#536069',teal:'#277F89',line:'#D7DFE3',pale:'#F1F4F5',ice:'#EAF4F5',white:'#FFFFFF'};
const build=path.join(workspaceDir,'build');
await fs.mkdir(build,{recursive:true});
await fs.mkdir(path.join(workspaceDir,'output'),{recursive:true});
const p=Presentation.create({slideSize:{width:1280,height:720}});
const s=p.slides.add();
s.background.fill=C.white;
function text(name,value,x,y,width,height,size,opts={}){
  const a=s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text=value;
  a.text.style={typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};
  return a;
}
function node(name,x,y,width,height,fill=C.pale){
  return s.shapes.add({geometry:'rect',name,position:{left:x,top:y,width,height},fill,line:{fill:C.line,width:1}});
}
function connect(source,target){
  return s.shapes.connect(source,target,{kind:'elbow',fromSide:'bottom',toSide:'top',line:{fill:C.teal,width:1.5},tail:{type:'triangle',width:'sm',length:'sm'}});
}
text('analysis-workflow-heading','PLANNED ANALYSIS WORKFLOW',762,238,446,31,22,{bold:true,color:C.teal});
const input=node('shared-room-hvac-input',762,277,446,65);
text('shared-input-title','Shared room + HVAC model',778,285,414,27,21,{bold:true});
text('shared-input-detail','Geometry, seats and operating settings',778,313,414,24,17.5,{color:C.secondary});
const energy=node('planned-energyplus-analysis',762,369,204,86,C.ice);
const airflow=node('planned-openfoam-analysis',1000,369,208,86,C.ice);
text('energyplus-title','EnergyPlus',778,377,172,27,21,{bold:true});
text('energyplus-outputs','Daily electricity\nThermal loads',778,406,172,46,17.5,{color:C.secondary});
text('openfoam-title','OpenFOAM',1016,377,176,27,21,{bold:true});
text('openfoam-outputs','Local temperature\nAir velocity',1016,406,176,46,17.5,{color:C.secondary});
const evidence=node('evidence-gate',762,479,446,54);
text('evidence-gate-title','Evidence check',778,486,414,25,19.5,{bold:true});
text('evidence-gate-detail','Inputs, run record, quality and freshness',778,511,414,23,16.5,{color:C.secondary});
const comfort=node('comfort-evaluation',762,560,138,63,C.ice);
const electricity=node('electricity-evaluation',916,560,138,63,C.ice);
const cost=node('cost-evaluation',1070,560,138,63,C.ice);
text('comfort-label','Comfort',776,569,112,26,19.5,{bold:true,color:C.teal});
text('comfort-detail','At each seat',776,596,112,23,16.5,{color:C.secondary});
text('electricity-label','Electricity',930,569,112,26,19.5,{bold:true,color:C.teal});
text('electricity-detail','kWh per day',930,596,112,23,16.5,{color:C.secondary});
text('cost-label','Cost',1084,569,112,26,19.5,{bold:true,color:C.teal});
text('cost-detail','Tariff + run',1084,596,112,23,16.5,{color:C.secondary});
connect(input,energy);connect(input,airflow);
connect(energy,evidence);connect(airflow,evidence);
connect(evidence,comfort);connect(evidence,electricity);connect(evidence,cost);
const patch=path.join(build,'product-function-patch.pptx');
await (await PresentationFile.exportPptx(p)).save(patch);
const preview=await p.export({slide:s,format:'png',scale:1.25});
await fs.writeFile(path.join(build,'product-function-patch.png'),new Uint8Array(await preview.arrayBuffer()));
const original=process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx');
const candidate=path.join(build,'candidate.pptx');
const merged=spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets','replace-product-function-region.py'),original,patch,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);
console.log(merged.stdout.trim());
const finalPath=path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.function-diagram.pptx');
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
