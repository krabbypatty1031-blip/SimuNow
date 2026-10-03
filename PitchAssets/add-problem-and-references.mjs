import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

// Add two researched slides without rebuilding the original deck. The Python
// package merger preserves original slide objects, masters, media and notes.
const projectRoot = process.env.PROJECT_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceDir = process.env.PITCH_WORK_DIR;
const skillDir = process.env.PRESENTATIONS_SKILL_DIR;
const pythonExecutable = process.env.PRESENTATIONS_PYTHON;
if (![workspaceDir, skillDir, pythonExecutable].every(p => p && path.isAbsolute(p))) {
  throw new Error('Set PITCH_WORK_DIR, PRESENTATIONS_SKILL_DIR and PRESENTATIONS_PYTHON to absolute runtime paths.');
}
const { resolvePresentationFont, applyPresentationChartFont, finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
const FONT = resolvePresentationFont({ fontFamily: 'Arial' });
const C = { ink:'#20282C', secondary:'#536069', muted:'#64727A', teal:'#277F89', cyan:'#57BCC7', grid:'#D7DFE3', white:'#FFFFFF' };
const build = path.join(workspaceDir, 'build');
await fs.mkdir(build, {recursive:true});
await fs.mkdir(path.join(workspaceDir, 'output'), {recursive:true});
const evidence = JSON.parse(await fs.readFile(path.join(projectRoot, 'PitchAssets', 'research-sources.json'), 'utf8'));
const hk = evidence.hongKong;
const hkShare = hk.airConditioningTJ / hk.totalElectricityTJ;
const officeShare = hk.officeAirConditioningTJ / hk.officeElectricityTJ;
const hkTWh = hk.airConditioningTJ / 3600;
const p = Presentation.create({slideSize:{width:1280,height:720}});
p.theme.colorScheme = { name:'SimuNow Architectural Light', themeColors:{accent1:C.teal,accent2:C.cyan,accent3:'#788D98',accent4:'#BDC9CE',accent5:'#D6E6E8',accent6:'#6B7880',bg1:C.white,bg2:'#F1F4F5',tx1:C.ink,tx2:C.secondary,dk1:C.ink,dk2:C.secondary,lt1:C.white,lt2:'#F1F4F5',hlink:C.teal,folHlink:C.secondary} };
function text(s,name,value,x,y,width,height,size=24,opts={}) {
  const a = s.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width,height},fill:'none',line:{fill:'none',width:0}});
  a.text = value;
  a.text.style = {typeface:FONT,fontSize:size,color:opts.color??C.ink,bold:opts.bold??false,alignment:opts.align??'left',verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};
  return a;
}
function slide(title,number) {
  const s=p.slides.add();
  s.background.fill=C.white;
  text(s,'simunow-brand','SimuNow',72,38,220,28,20,{bold:true});
  text(s,'slide-title',title,72,107,1136,68,52,{bold:true});
  text(s,`research-page-${number}`,String(number).padStart(2,'0'),1166,665,42,24,15,{color:C.muted,align:'right'});
  return s;
}
function bars(s, name, categories, values, colors, x,y,width,height,max,precision=0) {
  const chart=s.charts.add('bar',{
    position:{left:x,top:y,width,height},
    categories,
    series:[{name,values,fill:C.teal,points:colors.map((fill,idx)=>({idx,fill}))}],
    barOptions:{direction:'bar',grouping:'clustered',gapWidth:100},
    hasLegend:false,
    xAxis:{visible:true,min:0,max,majorUnit:max/2,numberFormatCode:'0%',textStyle:{typeface:FONT,fontSize:16,fill:C.muted},line:{fill:C.grid,width:0.7},majorGridlines:{fill:C.grid,width:0.7}},
    yAxis:{visible:true,textStyle:{typeface:FONT,fontSize:20,fill:C.ink},line:{fill:'none',width:0},majorGridlines:null},
    dataLabels:{showValue:true,position:'outEnd',textStyle:{typeface:FONT,fontSize:23,fill:C.ink,bold:true}},
    chartFill:C.white,chartLine:{fill:'none',width:0},plotAreaFill:C.white,plotAreaLine:{fill:'none',width:0}
  });
  chart.series.getItemAt(0).valuesFormatCode = precision ? '0.0%' : '0%';
  applyPresentationChartFont(chart,{fontFamily:FONT});
  return chart;
}

// Problem statement: observational statistics with explicit scope differences.
{
  const s=slide('Problem Statement',2);
  text(s,'problem-thesis','Cooling is a major electricity load, especially in offices',72,179,1136,37,27,{color:C.secondary});
  text(s,'hong-kong-heading','HONG KONG  /  2024',72,238,540,34,23,{bold:true,color:C.teal});
  text(s,'hong-kong-electricity',`${hkTWh.toFixed(1)} TWh`,72,278,530,74,64,{bold:true});
  text(s,'hong-kong-stat-caption','Electricity for the EMSD “Air Conditioning” category [1]',72,357,544,48,20,{color:C.secondary});
  text(s,'hong-kong-chart-title','Share of electricity within each scope',72,415,540,28,20,{bold:true});
  // Chart workbook records the same one-decimal percentage precision shown
  // to the audience; exact source TJ values and full ratios remain in notes.
  bars(s,'Air Conditioning share', ['All Hong Kong','Offices'],[Number(hkShare.toFixed(3)),Number(officeShare.toFixed(3))],[C.cyan,C.teal],72,448,544,112,0.6,1);

  text(s,'global-heading','GLOBAL  /  IEA 2026 ESTIMATE',694,238,514,34,23,{bold:true,color:C.teal});
  text(s,'global-electricity','≈2,900 TWh',694,278,514,74,58,{bold:true});
  text(s,'global-stat-caption','Annual building space-cooling electricity\nAround 50% growth since 2015 [2]',694,357,514,52,20,{color:C.secondary});
  text(s,'global-chart-title','Approx. cooling share: annual use vs peak [2]',694,415,514,28,20,{bold:true});
  bars(s,'Cooling share', ['Annual electricity','Peak power'],[0.10,0.30],[C.cyan,C.teal],694,448,514,112,0.4,0);

  text(s,'research-problem','Room operators need evidence to choose AC placement and settings\nthat balance electricity use with comfort at each seat.',72,587,832,63,25,{bold:true});
  const blob=new Uint8Array(await fs.readFile(path.join(projectRoot,'PitchAssets','problem-hong-kong-office.png')));
  s.images.add({blob,contentType:'image/png',alt:'Concept illustration of an air-conditioned Hong Kong office, not simulation evidence',fit:'contain',position:{left:942,top:568,width:266,height:88}});
  text(s,'problem-footnote','[1] EMSD (2026), Tables 12 and 39. HK includes heaters, fans, air purifiers and dehumidifiers.\n[2] IEA (10 Jul 2026). Space cooling excludes data centres. Annual energy and peak power use different denominators.',72,660,1080,42,13.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`Problem statement. These statistics establish the scale of electricity use, not SimuNow savings or validated performance.\n\n[1] Electrical and Mechanical Services Department (2026). Hong Kong Energy End-use Data 2026. ${evidence.sources[0].url}\nData year: 2024, not 2026. Table 12, printed p. 27 (PDF p. 28): Air Conditioning 50,193 TJ, total electricity 166,931 TJ. Calculation: 50,193 / 3,600 = 13.9425 TWh, displayed 13.9 TWh. 50,193 / 166,931 = ${hkShare}, displayed 30.1%. Table 39, printed p. 54 (PDF p. 55): office Air Conditioning 7,837 TJ, office total 17,179 TJ. Ratio ${officeShare}, displayed 45.6%. Values are official estimated end-use statistics, not individual-building meter observations. The EMSD category includes air-conditioning units and heaters plus fans, air cleaners/purifiers and dehumidifiers (Chronology item 21, printed p. 78 / PDF p. 79).\n\n[2] International Energy Agency (2026). Cooling a hotter world: El Niño meets strong growth in global electricity demand. Commentary, 10 July 2026. ${evidence.sources[1].url}\nIEA reports around 2,900 TWh of global building space-cooling electricity, 50% growth since 2015, approximately 10% of annual electricity consumption and 30% of peak demand. This commentary excludes cooling in data centres. The slide labels the source vintage because the paragraph does not explicitly assign a year to the 2,900 TWh estimate. Annual electricity is energy and peak power is demand. These shares have different denominators. Hong Kong and IEA categories are not harmonised and should not be used to calculate a direct local/global efficiency ratio.\n\nThe room-level decision need is the SimuNow product problem framing, based on Plans/References/01-product-scope.md and 03-experience-design.md. No measured waste fraction, savings percentage or comfort improvement is claimed. Supporting illustration generated with the built-in imagegen tool. Asset: PitchAssets/problem-hong-kong-office.png. Concept art only, without computed airflow, temperatures or measured comfort. Retrieved 3 October 2026.`);
}

// A single bibliography page covers new statistics and the source groups used
// in the original deck's notes. All web links are stored as PPT hyperlinks.
{
  const s=slide('References',14);
  text(s,'references-subtitle','Statistical sources, project evidence and illustration provenance',72,180,1136,37,25,{color:C.secondary});
  const left=72,right=688,w=520;
  text(s,'ref1-title','[1] EMSD (2026)',left,244,w,30,23,{bold:true});
  text(s,'ref1-body','Hong Kong Energy End-use Data 2026\n2024 statistics. Table 12, p. 27. Table 39, p. 54.\nCategory definition: revision 21, p. 78.',left,285,w,78,20,{color:C.secondary});
  text(s,'ref1-link','EMSD official report (PDF)',left,371,w,29,19,{color:C.teal});
  text(s,'ref2-title','[2] International Energy Agency (2026)',left,430,w,32,23,{bold:true});
  text(s,'ref2-body','Cooling a hotter world: El Niño meets strong\ngrowth in global electricity demand\nCommentary, 10 July 2026. Licence: CC BY 4.0.',left,472,w,80,20,{color:C.secondary});
  text(s,'ref2-link','IEA official commentary',left,560,w,29,19,{color:C.teal});

  text(s,'ref3-title','[3] Product and experience',right,244,w,30,23,{bold:true});
  text(s,'ref3-body','SimuNow project documents\nPlans/References/01-product-scope.md\nPlans/References/03-experience-design.md',right,283,w,73,19,{color:C.secondary});
  text(s,'ref4-title','[4] Architecture, contracts and physics',right,384,w,31,23,{bold:true});
  text(s,'ref4-body','Plans/References/02-architecture.md\nPlans/References/04-data-contracts.md\nPlans/References/05-computation-and-decision.md\nAGENTS.md',right,424,w,98,18,{color:C.secondary});
  text(s,'ref5-title','[5] Delivery evidence and roadmap',right,545,w,31,23,{bold:true});
  text(s,'ref5-body','README.md. Plans/Delivery/status.md and verification.md\nPlans/References/06-roadmap-and-backlog.md\nPlans/Phases/P1, P5, P6 and P7 work packages',right,584,w,72,17.5,{color:C.secondary});

  text(s,'reference-disclosure','Web sources accessed 3 Oct 2026. Project sources describe planned capabilities and documented progress.\nConcept illustrations: built-in imagegen, 2–3 Oct 2026. Assets and prompts in PitchAssets/. No artwork is simulation evidence.',72,665,1080,38,13.5,{color:C.muted});
  s.speakerNotes.textFrame.setText(`References for this presentation.\n\n[1] Electrical and Mechanical Services Department, Government of the Hong Kong Special Administrative Region (2026). Hong Kong Energy End-use Data 2026. Tables 12 and 39, pp. 27 and 54. Chronology of Major Revisions item 21, p. 78. ${evidence.sources[0].url}\n[2] International Energy Agency (2026). Cooling a hotter world: El Niño meets strong growth in global electricity demand. IEA, Paris. Commentary, 10 July 2026. Licence: CC BY 4.0. ${evidence.sources[1].url}\n[3] SimuNow (2026). Plans/References/01-product-scope.md and Plans/References/03-experience-design.md. Internal project design sources for slides 1, 3–6, 8, 10 and 13.\n[4] SimuNow (2026). Plans/References/02-architecture.md, Plans/References/04-data-contracts.md, Plans/References/05-computation-and-decision.md and AGENTS.md. Internal methodology and evidence constraints for slides 4, 6–9.\n[5] SimuNow (2026). README.md, Plans/Delivery/status.md, Plans/Delivery/verification.md, Plans/References/06-roadmap-and-backlog.md, Plans/Phases/P1-physics-spike.md, Plans/Phases/P5-decision-and-report.md, Plans/Phases/P6-capture-and-calibration.md and Plans/Phases/P7-optimization-and-release.md. Internal maturity and milestone sources for slides 11–12.\n\nIllustration provenance: cover-architecture-airflow.png, seat-airflow-study.png and room-model-exploded.png generated with the built-in imagegen tool on 2 Oct 2026. problem-hong-kong-office.png generated on 3 Oct 2026. Original and new prompts are in PitchAssets/imagegen-prompts.json and PitchAssets/problem-imagegen-prompt.json. Illustrations are concepts, not simulation or measurement evidence.\n\nExternal sources accessed 3 October 2026. Internal paths are relative to the SimuNow repository root. The deck does not claim that the planned numerical or comfort features are implemented.`);
}
const additions=path.join(build,'research-additions.pptx');
await (await PresentationFile.exportPptx(p)).save(additions);
for(let i=0;i<p.slides.items.length;i++) {
  const s=p.slides.items[i];
  const png=await p.export({slide:s,format:'png',scale:1.25});
  await fs.writeFile(path.join(build,`addition-${i+1}.png`),new Uint8Array(await png.arrayBuffer()));
}
const original=process.env.PITCH_ORIGINAL_PATH??path.join(build,'original.pptx');
const candidate=path.join(build,'candidate.pptx');
const merged=spawnSync(process.env.PITCH_MERGE_PYTHON??'python3',[path.join(projectRoot,'PitchAssets','insert-research-slides.py'),original,additions,candidate],{encoding:'utf8'});
if(merged.status!==0)throw new Error(merged.stderr||merged.stdout);
console.log(merged.stdout.trim());
const finalPath=path.join(workspaceDir,'output',process.env.PITCH_OUTPUT_NAME??'PitchDeck.researched.pptx');
const result=await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-heading-fit','--require-native-table-slide','8','--require-native-table-slide','11'],
  explicitTotalSlideCount:14,requiredNativeTableOwnerSlides:[8,11],requiredNativeChartOwnerSlides:[2],
  fontPolicy:{basis:'reference',families:[FONT],referencePath:original,referenceSha256:createHash('sha256').update(await fs.readFile(original)).digest('hex')},
  materializeLiteralChartWorkbooks:true,verifyArtifactToolImport:true,
  receiptPath:path.join(build,`${path.basename(finalPath)}.validation.json`)
});
console.log(JSON.stringify({finalPath,result}));
