import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const projectRoot = process.env.PROJECT_ROOT??path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const workspaceDir = process.env.PITCH_WORK_DIR;
const skillDir = process.env.PRESENTATIONS_SKILL_DIR;
const pythonExecutable = process.env.PRESENTATIONS_PYTHON;
if (![workspaceDir,skillDir,pythonExecutable].every(p=>p&&path.isAbsolute(p))) {
  throw new Error('Set the absolute presentation runtime and task paths.');
}
const {resolvePresentationFont,finalizePresentation} = await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const FONT = resolvePresentationFont({fontFamily:'Arial'});
const C = {ink:'#20282C',secondary:'#536069',muted:'#64727A',teal:'#277F89',cyan:'#57BCC7',white:'#FFFFFF',pale:'#F1F4F5'};
const build = path.join(workspaceDir,'build');
await fs.mkdir(build,{recursive:true});
await fs.mkdir(path.join(workspaceDir,'output'),{recursive:true});
const p = Presentation.create({slideSize:{width:1280,height:720}});
p.theme.colorScheme = {name:'SimuNow Architectural Light',themeColors:{accent1:C.teal,accent2:C.cyan,accent3:'#788D98',accent4:'#BDC9CE',accent5:'#D6E6E8',accent6:'#6B7880',bg1:C.white,bg2:C.pale,tx1:C.ink,tx2:C.secondary,dk1:C.ink,dk2:C.secondary,lt1:C.white,lt2:C.pale,hlink:C.teal,folHlink:C.secondary}};
function text(s,name,value,x,y,width,height,size=24,opts={}) {
  const a = s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text = value;
  a.text.style = {typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:opts.align??'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};
  return a;
}
const s = p.slides.add();
s.background.fill = C.white;
text(s,'simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
text(s,'slide-title','Introducing SimuNow',72,107,1136,68,52,{bold:true});
text(s,'product-definition','A Mac-first workspace for indoor AC configuration and analysis',72,179,1136,37,27,{color:C.secondary});
text(s,'page-4','04',1166,665,42,24,15,{color:C.muted,align:'right'});
text(s,'workspace-heading','ONE ROOM MODEL',72,238,650,31,22,{bold:true,color:C.teal});
text(s,'capabilities-heading','PLANNED PRODUCT CAPABILITIES',762,238,446,31,22,{bold:true,color:C.teal});
const imageBytes = new Uint8Array(await fs.readFile(path.join(projectRoot,'PitchAssets','product-workspace-concept.png')));
s.images.add({blob:imageBytes,contentType:'image/png',alt:'Generated concept of a planned Mac workspace with object navigation, a room model and an AC inspector. Not an actual product screenshot or simulation result.',fit:'contain',position:{left:72,top:280,width:650,height:316}});
text(s,'workspace-caption','Planned interface concept. Initial scope: one office or classroom.',72,604,650,27,14.5,{color:C.muted});
const capabilities = [
  ['01 / Room configuration','Geometry, furniture and occupied seats\nAC placement and operating settings'],
  ['02 / Linked energy and airflow','EnergyPlus for electricity and loads\nOpenFOAM for local airflow'],
  ['03 / Decision evaluation','Comfort at occupied positions\nElectricity and operating cost'],
  ['04 / Traceable evidence','Run IDs, input snapshots and quality\nEngine versions, mesh and settings'],
];
capabilities.forEach(([title,body],i)=>{
  const y=278+i*89;
  text(s,`capability-${i}-title`,title,762,y,446,30,22,{bold:true});
  text(s,`capability-${i}-body`,body,762,y+34,446,50,20,{color:C.secondary});
});
text(s,'platform-label','PLATFORM DESIGN',72,645,180,28,17,{bold:true,color:C.teal});
text(s,'platform-body','Mac workspace and inspector, with adaptive iPad and iPhone views.',267,644,941,31,20,{color:C.secondary});
text(s,'product-source','[4] AGENTS.md: product scope, interface guidelines, physical constraints and run records.\nProduct vision. Current: native app foundation. Numerical engines and decision evaluation are not connected.',72,682,1080,34,13.5,{color:C.muted});
const agentsPath = path.join(build,'AGENTS.source.md');
const sourceHash = createHash('sha256').update(await fs.readFile(agentsPath)).digest('hex');
s.speakerNotes.textFrame.setText(`Product definition [4]: SimuNow (2026), AGENTS.md. Sections: Project and priorities; Swift and interface guidelines; Physical and result constraints; Data and task conventions. Source snapshot dated 3 October 2026, SHA-256 ${sourceHash}.\n\nSimuNow is a Mac-first tool for indoor air-conditioner configuration and operation analysis, with compatibility goals for iOS and iPadOS. Its stated product vision connects EnergyPlus energy modelling and OpenFOAM airflow through one room model and evaluates comfort at occupied positions, electricity and cost. The initial scene is one office or classroom.\n\nThe room model describes geometry, furniture, occupied seats and heat sources, along with AC placement and operating inputs. Setpoint, supply temperature, cooling capacity, electrical input, airflow and air speed remain distinct quantities with units. The depicted inspector is conceptual and contains no numerical values.\n\nEnergyPlus and OpenFOAM are planned analyses. They do not currently form an implemented or validated product pipeline. Spatial comfort requires appropriate temperature, radiation, velocity, humidity, clothing and activity inputs. Cost needs a cited tariff. No savings percentage, measured satisfaction, PMV result, annual extrapolation or cooldown time is claimed.\n\nTraceable evidence follows AGENTS.md: immutable input snapshots, run and scenario identities, input hash, engine versions, solver settings, mesh and quality records. Completion, quality and current inputs are separate conditions. Invalid, unconverged or unsampled results cannot support a valid report or recommendation. These describe planned numerical evidence requirements, not a claim of completed numerical functions.\n\nThe planned Mac interface uses a workspace and inspector. iPad uses adaptive panes and iPhone retains accessible navigation. The page introduces this product direction rather than claiming that every platform interface is finished. The native application foundation exists; numerical engines are not connected.\n\nIllustration: PitchAssets/product-workspace-concept.png, generated by the built-in imagegen tool on 3 October 2026. Full prompt in PitchAssets/product-imagegen-prompt.json. Planned interface concept, not an actual application screenshot, measured data or computed simulation output. All slide headings, capability descriptions and disclosures are editable PowerPoint text objects.`);
const addition = path.join(build,'product-page.pptx');
await (await PresentationFile.exportPptx(p)).save(addition);
const png = await p.export({slide:s,format:'png',scale:1.25});
await fs.writeFile(path.join(build,'product-page.png'),new Uint8Array(await png.arrayBuffer()));
const original = process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx');
const candidate = path.join(build,'candidate.pptx');
const merged = spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets','replace-product-slide.py'),original,addition,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);
console.log(merged.stdout.trim());
const finalPath = path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.product-overview.pptx');
const result = await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-heading-fit','--require-native-table-slide','3','--require-native-table-slide','8','--require-native-table-slide','11'],
  explicitTotalSlideCount:14,requiredNativeTableOwnerSlides:[3,8,11],requiredNativeChartOwnerSlides:[2],
  fontPolicy:{basis:'reference',families:[FONT],referencePath:original,referenceSha256:createHash('sha256').update(await fs.readFile(original)).digest('hex')},
  verifyArtifactToolImport:true,
  receiptPath:path.join(build,`${path.basename(finalPath)}.validation.json`)
});
console.log(JSON.stringify({finalPath,result}));
