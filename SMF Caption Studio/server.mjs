import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = here;
const port = Number(process.env.PORT || 8787);
const python = process.env.SMF_PYTHON || (process.platform === 'win32'
  ? path.join(root,'.venv','Scripts','python.exe')
  : path.join(root,'.venv','bin','python'));
const ffmpeg = process.env.FFMPEG || (process.platform === 'win32'
  ? path.join(root,'runtime','ffmpeg','bin','ffmpeg.exe')
  : 'ffmpeg');

const publicDir = root;
const jobs = new Map();
const mime = {
  '.html':'text/html; charset=utf-8',
  '.js':'text/javascript; charset=utf-8',
  '.css':'text/css; charset=utf-8',
  '.json':'application/json; charset=utf-8',
  '.srt':'text/plain; charset=utf-8',
  '.mp4':'video/mp4',
  '.mov':'video/quicktime',
  '.webm':'video/webm'
};

function id(){return crypto.randomUUID();}
function json(res,status,obj){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(obj));}
function send(res,status,text,headers={}){res.writeHead(status,{'Content-Type':'text/plain; charset=utf-8',...headers});res.end(text);}
function tempRoot(){const p=path.join(os.tmpdir(),'smf-caption-studio');fs.mkdirSync(p,{recursive:true});return p;}
function safeFileName(s){return String(s||'video.mp4').replace(/[^a-zA-Z0-9._-]+/g,'_').slice(0,180) || 'video.mp4';}
function writeFileStream(req,out,limit=4*1024*1024*1024){
  return new Promise((resolve,reject)=>{
    let total=0;const ws=fs.createWriteStream(out);
    req.on('data',c=>{total+=c.length;if(total>limit){req.destroy();ws.destroy();reject(new Error('File exceeds 4 GB limit'));}});
    req.on('error',reject);ws.on('error',reject);ws.on('finish',()=>resolve(total));req.pipe(ws);
  });
}
function run(cmd,args,opts={}){
  return new Promise((resolve,reject)=>{
    const p=spawn(cmd,args,{windowsHide:true,...opts});
    let out='',err='';
    p.stdout?.on('data',d=>out+=d.toString());
    p.stderr?.on('data',d=>err+=d.toString());
    p.on('error',reject);p.on('close',code=>code===0?resolve({out,err}):reject(Object.assign(new Error(err.trim()||('Process exited '+code)),{code,out,err})));
  });
}
function renderASS(captions,style){
  const font=String(style?.font||'Arial Black').replace(/[{}]/g,'');
  const size=Number(style?.size||52);
  const bold=Number(style?.weight||900)>=700?1:0;
  const color=String(style?.color||'#FFFFFF');
  const accent=String(style?.accent||'#FF3349');
  const align = style?.align==='left'?1:style?.align==='right'?3:2;
  const posX = align===1?70:align===3?1010:540;
  const posY = Math.round((Number(style?.position||78)/100)*1920);
  const lines=[
    '[Script Info]','ScriptType: v4.00+','PlayResX: 1080','PlayResY: 1920','ScaledBorderAndShadow: yes','',
    '[V4+ Styles]','Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    'Style: Default,'+font+','+size+','+hexASS(color)+','+hexASS(accent)+',&HAA000000,&H55000000,'+bold+',0,0,0,100,100,0,0,1,3,2,'+align+',30,30,30,1','',
    '[Events]','Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text'
  ];
  for(const c of captions||[]){
    const words=(c.words&&c.words.length?c.words:[{word:c.text||'',start:c.start||0,end:c.end||0}]);
    let text='';
    for(let i=0;i<words.length;i++){
      const w=words[i], from=Math.round((w.start-c.start)*100), to=Math.round((w.end-c.start)*100);
      const dur=Math.max(1,to-from);
      const raw=String(w.word||'').replace(/[{}]/g,'');
      text += '{\\k'+dur+'}'+raw+' ';
    }
    const pos='\\pos('+posX+','+posY+')';
    lines.push('Dialogue: 0,'+assTime(c.start)+','+assTime(c.end)+',Default,,0,0,0,,'+pos+' '+text.trim());
  }
  return lines.join('\n');
}
function assTime(sec){sec=Math.max(0,Number(sec)||0);const h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),s=Math.floor(sec%60),cs=Math.floor((sec-Math.floor(sec))*100);return h+':'+String(m).padStart(2,'0')+':'+String(s).padStart(2,'0')+'.'+String(cs).padStart(2,'0');}
function hexASS(c){c=String(c||'#fff').replace('#','');if(c.length===3)c=c.split('').map(x=>x+x).join('');return '&H00'+c.slice(4,6)+c.slice(2,4)+c.slice(0,2);}
function getJob(j){return jobs.get(j);}
function inputInfo(file){return new Promise((resolve,reject)=>{spawn('ffprobe',['-v','error','-show_entries','format=duration:stream=width,height','-of','json',file],{windowsHide:true}).on('error',reject).on('close',()=>{try{const s=fs.readFileSync(file+'.probe.json','utf8');resolve(JSON.parse(s));}catch{resolve(null);}});});}

async function probe(file){
  try{
    const p=spawn('ffprobe',['-v','error','-show_entries','format=duration:stream=width,height','-of','json',file],{windowsHide:true});
    let out='';p.stdout.on('data',d=>out+=d);await new Promise((res,rej)=>{p.on('error',rej);p.on('close',c=>c?rej(new Error('ffprobe failed')):res())});const j=JSON.parse(out);
    const v=(j.streams||[]).find(x=>x.codec_type==='video')||{};return {duration:Number(j.format?.duration||0),width:Number(v.width||0),height:Number(v.height||0)};
  }catch{return {duration:0,width:0,height:0};}
}

function startTranscription(job,query){
  job.status='transcribing';job.stage='Starting Whisper';job.progress=2;
  const args=[path.join(root,'tools','transcribe.py'),job.input,'--model',query.model||'small','--language',query.language||'auto'];
  const child=spawn(python,args,{windowsHide:true,env:{...process.env,SMF_PROGRESS_DURATION:String(job.duration||0)}});
  let out='',err='';
  child.stdout.on('data',d=>out+=d.toString());
  child.stderr.on('data',d=>{
    const lines=d.toString().split(/\r?\n/);
    for(const line of lines){
      err+=line+'\n';
      const m=line.match(/^SMF_PROGRESS\s+(\d+(?:\.\d+)?)\s+\|\s+(.+)$/);
      if(m){job.progress=Number(m[1]);job.stage=m[2].trim();job.lastLog=line;}
    }
  });
  child.on('error',e=>{job.status='error';job.stage='Error';job.error=e.message;});
  child.on('close',code=>{
    if(code!==0){job.status='error';job.stage='Error';job.error=err.trim()||('Whisper exited with code '+code);job.lastLog=job.error.slice(-1200);return;}
    try{
      const result=JSON.parse(out.trim());if(result.error)throw new Error(result.error);
      job.transcript=result;job.duration=Number(result.duration||job.duration);job.status='transcribed';job.stage='Complete';job.progress=100;
    }catch(e){job.status='error';job.stage='Error';job.error=e.message;job.lastLog=out.slice(-1200);}
  });
}

async function startRender(job,format){
  job.status='rendering';job.stage='Preparing render';job.progress=2;
  const work=path.join(tempRoot(),job.id);fs.mkdirSync(work,{recursive:true});
  const ass=path.join(work,'captions.ass');fs.writeFileSync(ass,renderASS(job.captions,job.style),'utf8');
  const ext=format==='prores'?'.mov':format==='webm'?'.webm':'.mp4';
  const output=path.join(work,'SMF_'+safeFileName(job.fileName).replace(/\.[^.]+$/,'')+'_CAPTIONED'+ext);
  job.output=output;
  try{
    if(format==='mp4'){
      await run(ffmpeg,['-y','-i',job.input,'-vf',"ass="+ass.replace(/\\/g,'/').replace(/:/g,'\\:'),'-c:v','libx264','-preset','medium','-crf','18','-c:a','aac','-b:a','192k',output]);
    }else if(format==='prores'){
      await run(ffmpeg,['-y','-f','lavfi','-i','color=c=black@0.0:s=1080x1920:r=30:d='+Math.max(.1,job.duration),'-vf',"ass="+ass.replace(/\\/g,'/').replace(/:/g,'\\:'),'-c:v','prores_ks','-profile:v','4','-pix_fmt','yuva444p10le','-an',output]);
    }else{
      await run(ffmpeg,['-y','-i',job.input,'-vf',"ass="+ass.replace(/\\/g,'/').replace(/:/g,'\\:'),'-c:v','libvpx-vp9','-crf','30','-b:v','0','-c:a','libopus',output]);
    }
    job.status='done';job.stage='Complete';job.progress=100;
  }catch(e){job.status='error';job.stage='Error';job.error=e.message;job.lastLog=e.stderr||e.message;}
}

const server=http.createServer(async(req,res)=>{
  try{
    const u=new URL(req.url,'http://127.0.0.1:'+port);
    if(u.pathname==='/api/health'&&req.method==='GET'){
      const ai=fs.existsSync(python);const ff=fs.existsSync(ffmpeg)||ffmpeg==='ffmpeg';
      let fw=false,ver='';if(ai){try{const x=await run(python,['-c',"import faster_whisper; print(getattr(faster_whisper,'__version__','installed'))"]);fw=true;ver=x.out.trim().split(/\r?\n/).pop();}catch{}}
      return json(res,200,{ok:true,fasterWhisper:fw,whisperVersion:ver,ffmpeg:ff,python,server:'SMF Caption Studio'});
    }
    if(u.pathname==='/api/upload'&&req.method==='POST'){
      const jobId=id(),dir=path.join(tempRoot(),jobId);fs.mkdirSync(dir,{recursive:true});
      const fileName=safeFileName(decodeURIComponent(req.headers['x-file-name']||'video.mp4'));const input=path.join(dir,fileName);
      const bytes=await writeFileStream(req,input);const info=await probe(input);
      jobs.set(jobId,{id:jobId,input,fileName,status:'ready',stage:'Ready',progress:100,error:'',lastLog:'',duration:info.duration,width:info.width,height:info.height,captions:[],style:{}});
      return json(res,200,{jobId,fileName,bytes,...info});
    }
    const tr=u.pathname.match(/^\/api\/transcribe\/([\w-]+)$/);
    if(tr&&req.method==='POST'){
      const job=getJob(tr[1]);if(!job)return json(res,404,{error:'Job not found'});
      if(!fs.existsSync(python))return json(res,500,{error:'Private Python runtime is missing: '+python});
      startTranscription(job,{model:u.searchParams.get('model')||'small',language:u.searchParams.get('language')||'auto'});
      return json(res,202,{jobId:job.id,status:'transcribing'});
    }
    const cr=u.pathname.match(/^\/api\/captions\/([\w-]+)$/);
    if(cr&&req.method==='POST'){
      const job=getJob(cr[1]);if(!job)return json(res,404,{error:'Job not found'});
      const body=await readJSON(req);job.captions=Array.isArray(body.captions)?body.captions:[];job.style=body.style||{};job.status='ready';return json(res,200,{ok:true,captions:job.captions.length});
    }
    const rr=u.pathname.match(/^\/api\/render\/([\w-]+)$/);
    if(rr&&req.method==='POST'){
      const job=getJob(rr[1]);if(!job)return json(res,404,{error:'Job not found'});
      const body=await readJSON(req);if(Array.isArray(body.captions))job.captions=body.captions;if(body.style)job.style=body.style;const format=['mp4','prores','webm'].includes(body.format)?body.format:'mp4';startRender(job,format);return json(res,202,{jobId:job.id,status:'rendering',format});
    }
    const sr=u.pathname.match(/^\/api\/job\/([\w-]+)$/);
    if(sr&&req.method==='GET'){const j=getJob(sr[1]);if(!j)return json(res,404,{error:'Job not found'});return json(res,200,{id:j.id,fileName:j.fileName,status:j.status,stage:j.stage,progress:j.progress,error:j.error,lastLog:j.lastLog,duration:j.duration,transcript:j.transcript||null});}
    const dl=u.pathname.match(/^\/api\/download\/([\w-]+)$/);
    if(dl&&req.method==='GET'){const j=getJob(dl[1]);if(!j?.output||j.status!=='done')return send(res,404,'Output not ready');const ext=path.extname(j.output).toLowerCase();res.writeHead(200,{'Content-Type':mime[ext]||'application/octet-stream','Content-Disposition':'attachment; filename="'+path.basename(j.output)+'"','Cache-Control':'no-store'});return fs.createReadStream(j.output).pipe(res);}
    if(req.method==='GET'){
      let pathname=decodeURIComponent(u.pathname);if(pathname==='/')pathname='/SMF_Caption_Studio.html';
      const fp=path.resolve(root,'.'+pathname);if(!fp.startsWith(path.resolve(root)))return send(res,403,'Forbidden');
      fs.stat(fp,(e,st)=>{if(e||!st.isFile())return send(res,404,'Not found');const type=mime[path.extname(fp).toLowerCase()]||'application/octet-stream';res.writeHead(200,{'Content-Type':type,'Cache-Control':'no-store'});fs.createReadStream(fp).pipe(res);});return;
    }
    send(res,405,'Method not allowed');
  }catch(e){json(res,500,{error:e.message});}
});
function readJSON(req){return new Promise((resolve,reject)=>{const c=[];req.on('data',x=>c.push(x));req.on('end',()=>{try{resolve(JSON.parse(Buffer.concat(c).toString('utf8')||'{}'))}catch(e){reject(e)}});req.on('error',reject)});}
server.listen(port,'127.0.0.1',()=>console.log('SMF Caption Studio running at http://127.0.0.1:'+port));
