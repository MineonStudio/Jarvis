import Foundation

enum WebPage {
    static let html = #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
      <meta name="color-scheme" content="light dark">
      <title>文件传输</title>
      <style>
        :root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color-scheme:light dark;--accent:#2878e5;--green:#24a875;--red:#d84242;--line:color-mix(in srgb,CanvasText 12%,transparent);--surface:color-mix(in srgb,CanvasText 4%,Canvas)}
        *{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:Canvas;color:CanvasText}button{font:inherit}
        main{max-width:640px;margin:auto;padding:28px 18px max(42px,env(safe-area-inset-bottom))}
        header{display:flex;align-items:center;justify-content:space-between;margin-bottom:24px}h1{font-size:25px;letter-spacing:-.03em;margin:0}h2{font-size:18px;margin:0}
        .connected{color:var(--green);font-size:13px;font-weight:650}.connected::before{content:"";display:inline-block;width:7px;height:7px;margin-right:7px;border-radius:50%;background:currentColor}
        .card{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:20px;margin:14px 0;min-height:190px}.card.send{display:flex;flex-direction:column;height:clamp(250px,40vh,360px)}
        .heading{display:flex;align-items:center;gap:10px;margin-bottom:18px}.symbol{display:grid;place-items:center;width:34px;height:34px;border-radius:10px;background:color-mix(in srgb,var(--accent) 13%,transparent);color:var(--accent);font-size:19px}
        .pick{display:grid;place-items:center;min-height:68px;border:1px dashed color-mix(in srgb,var(--accent) 45%,transparent);border-radius:16px;background:color-mix(in srgb,var(--accent) 5%,transparent);cursor:pointer}.send .pick{flex:1}.pick strong{font-size:15px}.pick:active{transform:scale(.99)}.pick.disabled{opacity:.45;pointer-events:none}input[type=file]{display:none}
        .text-composer{display:flex;align-items:center;gap:8px;margin-top:10px;margin-bottom:16px}.text-composer input{flex:1;min-width:0;height:36px;padding:0 13px;border:1px solid color-mix(in srgb,CanvasText 17%,transparent);border-radius:999px;outline:0;background:color-mix(in srgb,CanvasText 4%,Canvas);color:CanvasText;font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;box-shadow:inset 0 1px 2px rgba(0,0,0,.035)}.text-composer input:focus{border-color:color-mix(in srgb,var(--accent) 58%,transparent);background:Canvas;box-shadow:0 0 0 3px color-mix(in srgb,var(--accent) 11%,transparent)}.text-composer input::placeholder{color:GrayText}.text-composer input:disabled{opacity:.55}.send-text{display:grid;place-items:center;width:32px;height:32px;flex:none;border:0;border-radius:50%;background:color-mix(in srgb,var(--accent) 10%,transparent);color:var(--accent);font-size:18px;line-height:1;cursor:pointer}.send-text:not(:disabled){background:color-mix(in srgb,var(--accent) 18%,transparent)}.send-text:disabled{color:GrayText;cursor:default}
        .empty{display:grid;place-items:center;min-height:116px;border:1px dashed var(--line);border-radius:16px;color:GrayText;font-size:14px}.empty.missing{border-color:color-mix(in srgb,#d88a28 55%,transparent);background:color-mix(in srgb,#d88a28 9%,Canvas);color:#c47b20}
        .task{display:none;padding:15px;border-radius:15px;background:color-mix(in srgb,CanvasText 5%,Canvas)}.task.visible{display:block}.task-head,.task-foot{display:flex;align-items:center;justify-content:space-between;gap:12px}.task-head strong{font-size:14px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.task-head span,.task-foot span{color:GrayText;font-size:12px}.task-foot{margin-top:10px}
        .text-history{display:flex;flex-direction:column;gap:12px;margin-top:12px}.text-record{display:block}.text-record .text-content{margin-top:10px}
        .text-content{margin-top:12px;padding:12px;border:1px solid var(--line);border-radius:12px;background:Canvas}.text-content pre{margin:0;max-height:180px;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.text-actions{display:flex;gap:8px;margin-top:10px}.text-actions .button{min-height:34px;padding:6px 12px;text-decoration:none;display:inline-flex;align-items:center;justify-content:center}
        .rail{height:7px;border-radius:99px;background:var(--line);overflow:hidden;margin:14px 0}.fill{height:100%;width:0;border-radius:inherit;background:linear-gradient(90deg,var(--accent),#70b3ff);transition:width .2s ease-out}.task.visible .fill::after{content:"";float:right;width:24px;height:100%;background:rgba(255,255,255,.7);filter:blur(5px);animation:flow 1.1s infinite}@keyframes flow{50%{opacity:.1}}
        .button{appearance:none;border:0;border-radius:11px;min-height:39px;padding:8px 15px;font-size:13px;font-weight:650;cursor:pointer;background:var(--accent);color:#fff}.button.secondary{color:CanvasText;background:color-mix(in srgb,CanvasText 10%,Canvas)}.button:disabled{opacity:.45}.task-actions{display:flex;gap:8px;flex-wrap:wrap}
        .notice{min-height:20px;margin-top:11px;font-size:13px}.error{color:var(--red)}.good{color:var(--green)}
        .scrim{position:fixed;inset:0;display:grid;place-items:center;background:rgba(0,0,0,.48);padding:20px;z-index:10}.scrim[hidden]{display:none}.dialog{width:min(100%,380px);padding:24px;background:Canvas;color:CanvasText;border:1px solid var(--line);border-radius:22px;box-shadow:0 18px 60px rgba(0,0,0,.25)}.dialog-icon{display:grid;place-items:center;width:46px;height:46px;border-radius:14px;background:color-mix(in srgb,var(--accent) 13%,transparent);color:var(--accent);font-size:25px}.dialog h2{margin:17px 0 10px}.dialog-name{overflow-wrap:anywhere;font-size:14px;font-weight:600}.dialog-size{color:GrayText;font-size:13px;margin-top:5px}.offer-text{max-height:38vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;padding:12px;border-radius:12px;background:var(--surface);font-size:14px;line-height:1.5}.actions{display:flex;gap:10px;margin-top:24px}.actions button{flex:1;min-height:46px;font-size:15px}
        .preview-box{width:min(100%,720px);max-height:min(90vh,840px);display:flex;flex-direction:column;background:Canvas;color:CanvasText;border:1px solid var(--line);border-radius:22px;box-shadow:0 18px 60px rgba(0,0,0,.25);overflow:hidden}.preview-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 16px;border-bottom:1px solid var(--line)}.preview-bar span{font-size:14px;font-weight:650;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.preview-body{min-height:240px;display:grid;place-items:center;padding:16px;overflow:auto}.preview-body img,.preview-body video{max-width:100%;max-height:70vh}.preview-body iframe{width:100%;height:70vh;border:0;background:Canvas}
        .file-preview{margin-top:12px;width:100%;border:1px solid var(--line);border-radius:12px;background:Canvas;overflow:hidden;min-height:64px;display:grid;place-items:center;padding:0;color:inherit;font:inherit}button.file-preview{cursor:pointer}.file-preview img,.file-preview video{width:100%;max-height:240px;object-fit:contain;background:color-mix(in srgb,CanvasText 4%,Canvas)}.file-preview pre{margin:0;width:100%;max-height:160px;overflow:auto;padding:12px;white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;text-align:left}.file-preview span{color:GrayText;font-size:13px;padding:16px}
        @media(prefers-reduced-motion:reduce){*,*::after{animation:none!important;transition:none!important}}
      </style>
    </head>
    <body>
      <main>
        <header><h1>文件传输 · {{DEVICE_IP}}</h1><span class="connected">已连接</span></header>
        <section class="card send">
          <div class="heading"><span class="symbol" aria-hidden="true">↑</span><h2>发送到 Mac</h2></div>
          <div class="text-composer"><input id="textInput" type="text" maxlength="30000" placeholder="请输入要传输的文本或链接" aria-label="请输入要传输的文本或链接" autocomplete="off"><button id="sendText" class="send-text" type="button" aria-label="发送文本" disabled>↑</button></div>
          <label id="pickLabel" class="pick" for="picker"><strong>选择文件，可多选</strong></label>
          <input id="picker" type="file" multiple>
        </section>
        <section class="card transfers">
          <div class="heading"><h2>传输列表</h2></div>
          <div id="uploadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="uploadName"></strong><span id="uploadPercent">0%</span></div>
            <div class="rail"><div id="uploadFill" class="fill"></div></div>
            <div id="uploadText" class="text-content" hidden><pre id="uploadTextOriginal"></pre><div class="text-actions"><button id="uploadCopyText" class="button secondary" type="button">复制</button><a id="uploadVisitLink" class="button" target="_blank" rel="noopener noreferrer" hidden>访问链接</a></div></div>
            <div class="task-foot"><span id="uploadState"></span><button id="cancelUpload" class="button secondary" type="button">取消</button></div>
          </div>
          <div id="uploadNotice" class="notice" role="status" aria-live="polite"></div>
          <div id="downloadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="downloadName"></strong><span id="downloadPercent">0%</span></div>
            <div class="rail"><div id="downloadFill" class="fill"></div></div>
            <div id="downloadText" class="text-content" hidden><pre id="downloadTextOriginal"></pre><div class="text-actions"><button id="downloadCopyText" class="button secondary" type="button">复制</button><a id="downloadVisitLink" class="button" target="_blank" rel="noopener noreferrer" hidden>访问链接</a></div></div>
            <div class="task-foot"><span id="downloadState"></span><div class="task-actions"><button id="cancelDownload" class="button secondary" type="button">取消</button><button id="openDownload" class="button" type="button" hidden>打开</button></div></div>
          </div>
          <div id="downloadNotice" class="notice" role="status" aria-live="polite"></div>
          <div id="receivedFiles" class="text-history" aria-label="收到的文件"></div>
          <div id="textHistory" class="text-history" aria-label="文本传输记录" aria-live="polite"></div>
        </section>
      </main>
      <div id="offerModal" class="scrim" hidden>
        <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="offerTitle">
          <div id="offerIcon" class="dialog-icon" aria-hidden="true">↙</div><h2 id="offerTitle">接收文件</h2>
          <div id="offerName" class="dialog-name"></div><div id="offerSize" class="dialog-size"></div><div id="offerText" class="offer-text" hidden></div>
          <div class="actions"><button id="decline" class="button secondary" type="button">取消</button><button id="accept" class="button" type="button">下载</button></div>
        </div>
      </div>
      <div id="filePreview" class="scrim" hidden>
        <div class="preview-box" role="dialog" aria-modal="true" aria-labelledby="previewName">
          <div class="preview-bar"><span id="previewName"></span><div class="task-actions"><button id="previewOpen" class="button" type="button">打开</button><button id="closePreview" class="button secondary" type="button">关闭</button></div></div>
          <div class="preview-body">
            <img id="previewImage" alt="" hidden>
            <video id="previewVideo" controls playsinline hidden></video>
            <iframe id="previewFrame" hidden></iframe>
            <p id="previewFallback" hidden>此文件无法在页面中预览</p>
          </div>
        </div>
      </div>
      <script>
        const picker=document.getElementById('picker'),pickLabel=document.getElementById('pickLabel'),uploadTask=document.getElementById('uploadTask'),uploadNotice=document.getElementById('uploadNotice'),downloadTask=document.getElementById('downloadTask'),downloadNotice=document.getElementById('downloadNotice'),offerModal=document.getElementById('offerModal'),filePreview=document.getElementById('filePreview'),textInput=document.getElementById('textInput'),sendTextButton=document.getElementById('sendText');
        const maxFileBytes=2*1073741824,previewLimit=32*1024*1024;
        const textHistoryKey='jarvis.file-transfer.text-history:'+location.host+location.search;
        let textRecords=[];
        try{const saved=JSON.parse(sessionStorage.getItem(textHistoryKey)||'[]');if(Array.isArray(saved))textRecords=saved.filter(item=>item&&typeof item.id==='string'&&typeof item.text==='string'&&['upload','download'].includes(item.direction))}catch{}
        let activeUpload=null,activeDownload=null,activeTextSend=null,currentOffer=null,checkingOffer=false,acceptingText=false,dismissedOfferID=null,lastDownload=null,lastPreviewUrl=null,uploadQueue=[],acceptedDownloadBatch=null,maxBatch=50;
        const receivedKey='jarvis.file-transfer.received:'+location.host+location.search;
        let receivedFiles=[],previewRecord=null,previewGeneration=0;
        try{const saved=JSON.parse(sessionStorage.getItem(receivedKey)||'[]');if(Array.isArray(saved))receivedFiles=saved.filter(item=>item&&typeof item.id==='string'&&typeof item.name==='string')}catch{}
        const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
        function size(n){if(n<1000)return n+' B';if(n<1000000)return Math.round(n/1000)+' KB';if(n<1000000000)return(n/1000000).toFixed(1)+' MB';return(n/1000000000).toFixed(2)+' GB'}
        function syncSendControls(){const locked=!!(activeUpload||activeDownload||activeTextSend||currentOffer||acceptingText||acceptedDownloadBatch);picker.disabled=locked;textInput.disabled=locked;pickLabel.classList.toggle('disabled',locked);sendTextButton.disabled=locked||!textInput.value.trim()}
        function setTask(prefix,name,status,ratio){document.getElementById(prefix+'Name').textContent=name;document.getElementById(prefix+'State').textContent=status;const pct=Math.max(0,Math.min(100,Math.round(ratio*100)));document.getElementById(prefix+'Percent').textContent=pct+'%';document.getElementById(prefix+'Fill').style.width=pct+'%'}
        function linkURL(text){try{const url=new URL(text.trim());return ['http:','https:'].includes(url.protocol)?url.href:null}catch{return null}}
        function clearTextTransfer(prefix){document.getElementById(prefix+'Text').hidden=true;document.getElementById(prefix+'TextOriginal').textContent='';document.getElementById(prefix+'VisitLink').hidden=true}
        function showTextTransfer(prefix,text){const value=String(text??'');document.getElementById(prefix+'TextOriginal').textContent=value;const link=linkURL(value),visit=document.getElementById(prefix+'VisitLink');visit.hidden=!link;if(link)visit.href=link;document.getElementById(prefix+'Text').hidden=false;document.getElementById(prefix+'CopyText').onclick=async()=>{try{await copyText(value);prefix==='upload'?notice('文本已复制'):receiveNotice('文本已复制')}catch{prefix==='upload'?notice('复制失败',true):receiveNotice('复制失败',true)}}}
        function renderTextHistory(){
          const history=document.getElementById('textHistory');history.replaceChildren();
          for(const record of textRecords){
            const card=document.createElement('article');card.className='task text-record';card.dataset.transferId=record.id;card.dataset.direction=record.direction;
            const heading=document.createElement('div');heading.className='task-head';const title=document.createElement('strong');title.textContent=record.direction==='download'?'收到的文本':'发送的文本';const state=document.createElement('span');state.textContent=record.status||'已接收';state.className=record.error?'error':'';heading.append(title,state);
            const content=document.createElement('div');content.className='text-content';const original=document.createElement('pre');original.textContent=record.text;
            const actions=document.createElement('div');actions.className='text-actions';const copy=document.createElement('button');copy.type='button';copy.className='button secondary';copy.textContent='复制';copy.onclick=async()=>{try{await copyText(record.text);state.textContent='文本已复制';state.className=''}catch{state.textContent='复制失败，请重试';state.className='error'}};actions.append(copy);
            const url=linkURL(record.text);if(url){const visit=document.createElement('a');visit.className='button';visit.textContent='访问链接';visit.href=url;visit.target='_blank';visit.rel='noopener noreferrer';actions.append(visit)}
            content.append(original,actions);card.append(heading,content);history.append(card);
          }
        }
        function rememberTextTransfer(direction,id,text,status,error=false){
          const record={direction,id:String(id),text:String(text??''),status,error};const index=textRecords.findIndex(item=>item.id===record.id&&item.direction===direction);
          if(index<0)textRecords.unshift(record);else textRecords[index]=record;
          try{sessionStorage.setItem(textHistoryKey,JSON.stringify(textRecords))}catch{}
          renderTextHistory();
        }
        renderTextHistory();
        renderReceivedFiles();
        async function copyText(value){if(navigator.clipboard?.writeText){try{await navigator.clipboard.writeText(value);return}catch{}}const field=document.createElement('textarea');field.value=value;field.style.position='fixed';field.style.opacity='0';document.body.append(field);field.select();const copied=document.execCommand('copy');field.remove();if(!copied)throw Error('复制失败')}
        function notice(text,error=false){uploadNotice.textContent=text;uploadNotice.className='notice '+(error?'error':'good')}
        function receiveNotice(text,error=false){downloadNotice.textContent=text;downloadNotice.className='notice '+(error?'error':'good')}
        function fileUrl(id,inline=false){const token=new URLSearchParams(location.search).get('t')||'';return '/api/file?id='+encodeURIComponent(id)+'&t='+encodeURIComponent(token)+(inline?'&inline=1':'')}
        function mimeOf(name,fallback){const dot=String(name||'').lastIndexOf('.');const ext=dot>0?name.slice(dot+1).toLowerCase():'';return ({png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',gif:'image/gif',webp:'image/webp',svg:'image/svg+xml',heic:'image/heic',heif:'image/heif',txt:'text/plain',text:'text/plain',md:'text/plain',csv:'text/plain',log:'text/plain',json:'application/json',pdf:'application/pdf',mp4:'video/mp4',mov:'video/quicktime',m4v:'video/mp4',mp3:'audio/mpeg',m4a:'audio/mp4',wav:'audio/wav'}[ext])||fallback||'application/octet-stream'}
        function batchLabel(offer,batched){const names=Array.isArray(offer.names)?offer.names.filter(item=>typeof item==='string'&&item):[];if(names.length>1){const shown=names.slice(0,6).join('、');return names.length>6?shown+' 等 '+names.length+' 个文件':shown}return batched?offer.batchIndex+'/'+offer.batchCount+' · '+offer.name:offer.name}
        function hidePreviewMedia(){['previewImage','previewVideo','previewFrame','previewFallback'].forEach(id=>document.getElementById(id).hidden=true);const video=document.getElementById('previewVideo');video.pause();video.removeAttribute('src');video.load();document.getElementById('previewImage').removeAttribute('src');document.getElementById('previewFrame').removeAttribute('src')}
        function closePreview(){filePreview.hidden=true;hidePreviewMedia();if(lastPreviewUrl){URL.revokeObjectURL(lastPreviewUrl);lastPreviewUrl=null}}
        function showUpload(file,item){clearTextTransfer('upload');uploadTask.classList.add('visible');uploadTask.classList.remove('error');document.getElementById('cancelUpload').hidden=false;pickLabel.hidden=true;picker.disabled=true;const label=item&&item.count>1?item.index+'/'+item.count+' · '+file.name:file.name;setTask('upload',label,'等待 Mac 接收 · '+size(file.size),0)}
        function finishUpload(text,error=false){const cancelled=text==='已取消',stopBatch=cancelled||(error&&!activeUpload?.sending);if(stopBatch)uploadQueue.length=0;const next=stopBatch?null:uploadQueue.shift();activeUpload=null;document.getElementById('cancelUpload').hidden=true;const status=cancelled?'已取消':(error?'发送失败':'已完成');setTask('upload',document.getElementById('uploadName').textContent,status,error?0:1);uploadTask.classList.add('visible');uploadTask.classList.toggle('error',error);if(next){offerQueuedUpload(next);return}pickLabel.hidden=false;picker.value='';syncSendControls();notice(text,error)}
        async function post(url){return fetch(url,{method:'POST',cache:'no-store'})}
        function enqueueUploads(files){
          if(activeUpload||activeDownload||activeTextSend||currentOffer||acceptingText||acceptedDownloadBatch){notice('当前有传输任务',true);return}
          const list=[...files],ready=list.filter(file=>file.size<=maxFileBytes).slice(0,maxBatch);
          if(list.some(file=>file.size>maxFileBytes))notice('超过 2 GB 的文件已跳过',true);
          else if(list.length>ready.length)notice('一次最多发送 50 个文件',true);
          if(!ready.length)return;
          const batch=ready.length>1?newBatchID():'';
          const names=ready.map(file=>file.name),packed=JSON.stringify(names);
          uploadQueue=ready.map((file,index)=>({file,batch,index:index+1,count:ready.length,names:index===0&&packed.length<=6000?names:null}));
          offerQueuedUpload(uploadQueue.shift());
        }
        function offerQueuedUpload(item){
          const file=item.file,task={id:null,file,xhr:null,finished:false,sending:false};activeUpload=task;syncSendControls();showUpload(file,item);notice(item.count>1?item.index+'/'+item.count:'');
          const listed=item.names?'&names='+encodeURIComponent(JSON.stringify(item.names)):'';
          const extra=item.batch?'&batch='+encodeURIComponent(item.batch)+'&index='+item.index+'&count='+item.count+listed:'';
          post('/api/offer-upload?name='+encodeURIComponent(file.name)+'&size='+file.size+extra).then(async response=>{if(!response.ok)throw Error(response.status===409?'当前有传输任务':'发送失败');task.id=(await response.json()).id;if(activeUpload!==task){await post('/api/cancel?id='+encodeURIComponent(task.id));return}watchUpload(task)}).catch(error=>{if(activeUpload===task)finishUpload(error.message||'发送失败',true)});
        }
        picker.onchange=()=>{const files=picker.files?[...picker.files]:[];picker.value='';if(files.length)enqueueUploads(files)};
        textInput.oninput=syncSendControls;
        textInput.onkeydown=event=>{if(event.key==='Enter'&&!event.isComposing){event.preventDefault();sendText()}};
        async function sendText(){
          const text=textInput.value;if(!text.trim()||activeUpload||activeDownload||activeTextSend||currentOffer||acceptingText||acceptedDownloadBatch)return;
          const task={id:null,localID:'local-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2),finished:false,text};activeTextSend=task;syncSendControls();uploadTask.classList.add('visible');uploadTask.classList.remove('error');document.getElementById('cancelUpload').hidden=true;showTextTransfer('upload',text);setTask('upload','文本消息','正在发送',0);notice('正在发送文本…');
          try{const response=await fetch('/api/offer-text',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});if(!response.ok)throw Error(response.status===409?'当前有传输任务':'发送失败');task.id=(await response.json()).id;textInput.value='';notice('等待 Mac 确认');watchTextSend(task)}catch(error){finishTextSend(task,error.message||'发送失败',true)}
        }
        sendTextButton.onclick=sendText;
        function finishTextSend(task,status,error=false){
          if(activeTextSend!==task)return;activeTextSend=null;
          rememberTextTransfer('upload',task.id||task.localID,task.text,status,error);
          uploadTask.classList.remove('visible');clearTextTransfer('upload');syncSendControls();notice(status,error);
        }
        async function watchTextSend(task){for(let i=0;i<600&&activeTextSend===task;i++){await wait(500);try{const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const state=await response.json();if(state.status==='已完成'){finishTextSend(task,'已接收');return}if(state.status==='失败'||state.status==='已取消'){finishTextSend(task,state.detail||state.status,true);return}}catch{}}if(activeTextSend===task)finishTextSend(task,'等待超时',true)}
        function sendUpload(task){
          if(task.sending||task.finished)return;task.sending=true;const label=document.getElementById('uploadName').textContent||task.file.name;setTask('upload',label,'正在发送',0);
          const xhr=new XMLHttpRequest();task.xhr=xhr;
          xhr.open('PUT','/api/upload?name='+encodeURIComponent(task.file.name)+'&id='+encodeURIComponent(task.id));
          xhr.upload.onprogress=e=>{if(e.lengthComputable)setTask('upload',label,'正在发送',e.loaded/e.total)};
          xhr.onload=()=>{if(task.finished)return;if(xhr.status===201)finishUpload('已发送：'+task.file.name);else finishUpload(xhr.responseText||'发送失败',true)};
          xhr.onerror=()=>{if(!task.finished)finishUpload('连接中断',true)};
          xhr.onabort=()=>{if(!task.finished)finishUpload('已取消',true)};
          xhr.send(task.file);
        }
        async function watchUpload(task){
          let failures=0;
          while(activeUpload===task&&!task.finished){await wait(500);if(activeUpload!==task)return;try{
            const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const progress=await response.json();failures=0;
            if(progress.status==='等待发送')sendUpload(task);
            if(progress.status==='失败'||progress.status==='已取消'){task.finished=true;task.xhr?.abort();finishUpload(progress.detail||progress.status,true);return}
          }catch{if(++failures>20){task.finished=true;task.xhr?.abort();finishUpload('连接中断',true);return}}}
        }
        document.getElementById('cancelUpload').onclick=async()=>{const task=activeUpload;if(!task)return;task.finished=true;if(task.id)try{await post('/api/cancel?id='+encodeURIComponent(task.id))}catch{}task.xhr?.abort();finishUpload('已取消')};
        async function checkOffer(){
          if(checkingOffer||activeUpload||activeDownload||activeTextSend||acceptingText)return;checkingOffer=true;
          try{const response=await fetch('/api/offer',{cache:'no-store'});if(response.status===204){currentOffer=null;dismissedOfferID=null;offerModal.hidden=true;syncSendControls()}else if(response.status===200){const offer=await response.json();if(offer.id!==dismissedOfferID&&!activeUpload&&!activeDownload&&!activeTextSend){if(offer.type!=='text'&&offer.batchID&&offer.batchID===acceptedDownloadBatch){currentOffer=null;offerModal.hidden=true;startFileDownload(offer,false);return}currentOffer=offer;syncSendControls();const isText=offer.type==='text',batched=!isText&&Number(offer.batchCount)>1;document.getElementById('offerIcon').hidden=isText;document.getElementById('offerTitle').textContent=isText?'来自 Mac 的文本':(batched?'接收 '+offer.batchCount+' 个文件':'接收文件');document.getElementById('offerName').textContent=batchLabel(offer,batched);document.getElementById('offerName').hidden=isText;document.getElementById('offerSize').textContent=offer.displaySize||size(offer.size);document.getElementById('offerSize').hidden=isText;const text=document.getElementById('offerText');text.textContent=isText?offer.text:'';text.hidden=!isText;document.getElementById('accept').textContent=isText?'复制':(batched?'全部接收':'下载');offerModal.hidden=false}}}catch{}finally{checkingOffer=false}
        }
        setInterval(checkOffer,700);checkOffer();
        document.getElementById('decline').onclick=async()=>{const offer=currentOffer;if(!offer)return;acceptedDownloadBatch=null;currentOffer=null;dismissedOfferID=offer.id;offerModal.hidden=true;syncSendControls();try{await post('/api/cancel?id='+encodeURIComponent(offer.id))}catch{}};
        document.getElementById('accept').onclick=async()=>{
          const offer=currentOffer;if(!offer)return;currentOffer=null;dismissedOfferID=offer.id;offerModal.hidden=true;
          if(offer.type==='text'){
            acceptingText=true;syncSendControls();rememberTextTransfer('download',offer.id,offer.text,'已接收');
            let copied=false;try{await copyText(offer.text);copied=true}catch{}
            try{
              const response=await post('/api/accept-text?id='+encodeURIComponent(offer.id));if(!response.ok)throw Error('接收确认失败');
              rememberTextTransfer('download',offer.id,offer.text,copied?'已复制到剪贴板':'已接收，可手动复制');receiveNotice(copied?'':'文本已保留，可在记录中复制');
            }catch{dismissedOfferID=null;rememberTextTransfer('download',offer.id,offer.text,'文本已保留，接收确认失败',true);receiveNotice('接收确认失败，请重试',true)}
            acceptingText=false;syncSendControls();return
          }
          startFileDownload(offer,true);
        };
        function newBatchID(){const bytes=new Uint8Array(16);if(globalThis.crypto?.getRandomValues)crypto.getRandomValues(bytes);else for(let i=0;i<16;i++)bytes[i]=Math.random()*256|0;bytes[6]=bytes[6]&15|64;bytes[8]=bytes[8]&63|128;const hex=Array.from(bytes,value=>value.toString(16).padStart(2,'0')).join('');return hex.slice(0,8)+'-'+hex.slice(8,12)+'-'+hex.slice(12,16)+'-'+hex.slice(16,20)+'-'+hex.slice(20)}
        function rememberReceivedFile(task){const record={id:String(task.id),name:String(task.name||'文件'),blob:task.blob||null};const index=receivedFiles.findIndex(item=>item.id===record.id);if(index<0)receivedFiles.unshift(record);else{record.blob=record.blob||receivedFiles[index].blob;record.urls=receivedFiles[index].urls;record.sniffed=receivedFiles[index].sniffed;receivedFiles[index]=record}try{sessionStorage.setItem(receivedKey,JSON.stringify(receivedFiles.map(item=>({id:item.id,name:item.name}))))}catch{}renderReceivedFiles()}
        function renderReceivedFiles(){previewGeneration++;const generation=previewGeneration;const list=document.getElementById('receivedFiles');list.replaceChildren();for(const record of receivedFiles){const card=document.createElement('article');card.className='task text-record';const heading=document.createElement('div');heading.className='task-head';const title=document.createElement('strong');title.textContent=record.name;const state=document.createElement('span');state.textContent='已接收';heading.append(title,state);const actions=document.createElement('div');actions.className='text-actions';const preview=document.createElement('button');preview.type='button';preview.className='button';preview.textContent='预览';preview.onclick=()=>openReceived(record);const open=document.createElement('button');open.type='button';open.className='button secondary';open.textContent='打开';open.onclick=()=>openStoredFile(record);actions.append(preview,open);card.append(heading,actions);mountReceivedPreview(card,record,generation);list.append(card)}}
        function insertPreview(card,node){const actions=card.querySelector('.text-actions');actions?card.insertBefore(node,actions):card.append(node)}
        function objectURL(record,type){const key=type||'application/octet-stream';record.urls=record.urls||{};if(record.urls[key])return record.urls[key];const blob=!record.blob||record.blob.type===key?record.blob:record.blob.slice(0,record.blob.size,key);record.urls[key]=URL.createObjectURL(blob);return record.urls[key]}
        function mountImagePreview(card,record,type){const button=document.createElement('button');button.type='button';button.className='file-preview';button.setAttribute('aria-label','预览 '+record.name);const img=document.createElement('img');img.alt=record.name;img.src=record.blob?objectURL(record,type||mimeOf(record.name)):fileUrl(record.id,true);button.append(img);button.onclick=()=>openReceived(record);insertPreview(card,button)}
        async function previewText(record){if(record.blob)return record.blob.slice(0,4096).text();const response=await fetch(fileUrl(record.id,true),{cache:'no-store',headers:{Range:'bytes=0-4095'}});if(!response.ok)throw Error('无法打开文件');return response.text()}
        async function mountTextPreview(card,record,generation){const box=document.createElement('div');box.className='file-preview';const pre=document.createElement('pre');pre.textContent='正在加载预览…';box.append(pre);insertPreview(card,box);try{const text=await previewText(record);if(generation!==previewGeneration||!card.isConnected)return;pre.textContent=text.length>800?text.slice(0,800)+'…':text}catch{if(generation===previewGeneration&&card.isConnected)pre.textContent='点预览查看全文'}}
        function typeFromBytes(bytes){if(bytes.length>=8&&bytes[0]===0x89&&bytes[1]===0x50&&bytes[2]===0x4e&&bytes[3]===0x47)return 'image/png';if(bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)return 'image/jpeg';if(bytes.length>=6&&bytes[0]===0x47&&bytes[1]===0x49&&bytes[2]===0x46)return 'image/gif';if(bytes.length>=12&&bytes[0]===0x52&&bytes[1]===0x49&&bytes[2]===0x46&&bytes[3]===0x46&&bytes[8]===0x57&&bytes[9]===0x45&&bytes[10]===0x42&&bytes[11]===0x50)return 'image/webp';const head=new TextDecoder().decode(bytes.slice(0,16));if(head.startsWith('%PDF'))return 'application/pdf';if(!bytes.includes(0)&&bytes.length&&bytes.filter(value=>value===9||value===10||value===13||(value>=32&&value<127)).length/bytes.length>0.9)return 'text/plain';return ''}
        async function sniffedType(record){if(record.sniffed)return record.sniffed;const type=mimeOf(record.name);if(type!=='application/octet-stream')return type;try{let bytes;if(record.blob)bytes=new Uint8Array(await record.blob.slice(0,512).arrayBuffer());else{const response=await fetch(fileUrl(record.id,true),{cache:'no-store',headers:{Range:'bytes=0-511'}});if(!response.ok)throw Error();bytes=new Uint8Array(await response.arrayBuffer())}record.sniffed=typeFromBytes(bytes)||type}catch{record.sniffed=type}return record.sniffed}
        async function mountReceivedPreview(card,record,generation){let type=record.sniffed||mimeOf(record.name);if(type==='application/octet-stream'){type=await sniffedType(record);if(generation!==previewGeneration||!card.isConnected)return}if(type.startsWith('image/'))mountImagePreview(card,record,type);else if(type.startsWith('text/')||type==='application/json')mountTextPreview(card,record,generation)}
        function canPreview(type){return type.startsWith('image/')||type.startsWith('video/')||type.startsWith('audio/')||type==='application/pdf'||type.startsWith('text/')||type==='application/json'}
        function showPreview(name,type,url){hidePreviewMedia();document.getElementById('previewName').textContent=name;if(type.startsWith('image/')){const img=document.getElementById('previewImage');img.src=url;img.hidden=false}else if(type.startsWith('video/')||type.startsWith('audio/')){const media=document.getElementById('previewVideo');media.src=url;media.hidden=false}else if(type==='application/pdf'||type.startsWith('text/')||type==='application/json'){const frame=document.getElementById('previewFrame');frame.src=url;frame.hidden=false}else{document.getElementById('previewFallback').hidden=false}filePreview.hidden=false;receiveNotice('')}
        async function openReceived(record){const name=record.name||'文件';previewRecord=record;try{let type=record.sniffed||mimeOf(name);if(type==='application/octet-stream')type=await sniffedType(record);if(!canPreview(type)){showPreview(name,'','');return}showPreview(name,type,record.blob?objectURL(record,type):fileUrl(record.id,true))}catch(error){receiveNotice(error.message||'打开失败',true)}}
        function openStoredFile(record){previewRecord=record;try{if(record.blob){window.open(objectURL(record,record.sniffed||record.blob.type||mimeOf(record.name)),'_blank');return}const link=document.createElement('a');link.href=fileUrl(record.id,true);link.target='_blank';link.rel='noopener';document.body.append(link);link.click();link.remove()}catch(error){receiveNotice(error.message||'打开失败',true)}}
        function startFileDownload(offer,userGesture){if(offer.batchID&&Number(offer.batchCount)>1)acceptedDownloadBatch=offer.batchID;clearTextTransfer('download');const label=Number(offer.batchCount)>1?offer.batchIndex+'/'+offer.batchCount+' · '+offer.name:offer.name;const task={id:offer.id,name:offer.name,label,finished:false,batchIndex:Number(offer.batchIndex)||0,batchCount:Number(offer.batchCount)||0,controller:new AbortController(),browserStarted:false,pulling:false,bytesReady:false,serverDone:false,blob:null,fallback:null};activeDownload=task;lastDownload=task;syncSendControls();downloadTask.style.display='';downloadTask.classList.add('visible');downloadTask.classList.remove('error');document.getElementById('cancelDownload').hidden=false;document.getElementById('openDownload').hidden=true;receiveNotice('');setTask('download',label,'等待系统确认',0);const link=document.createElement('a');link.href=fileUrl(offer.id);link.download=offer.name||'文件';document.body.append(link);link.click();link.remove();if(!userGesture)task.fallback=setTimeout(()=>{if(activeDownload===task&&!task.browserStarted)pullDownload(task)},2000);watchDownload(task)}
        async function pullDownload(task){if(task.pulling||task.finished||task.browserStarted)return;task.pulling=true;try{const response=await fetch(fileUrl(task.id),{cache:'no-store',signal:task.controller.signal});if(!response.ok)throw Error('接收失败');const length=Number(response.headers.get('Content-Length')||0);if(length>previewLimit){const reader=response.body&&response.body.getReader?response.body.getReader():null;if(reader){while(!(await reader.read()).done){}}else await response.arrayBuffer()}else task.blob=await response.blob();task.bytesReady=true;noteDownloadReady(task)}catch(error){if(task.finished||error?.name==='AbortError'||activeDownload!==task)return;finishDownload(task,'接收失败',true)}}
        function noteDownloadReady(task){if(activeDownload!==task||task.finished||!task.serverDone)return;if(task.pulling&&!task.bytesReady&&!task.browserStarted)return;finishDownload(task,'传输已完成')}
        function finishDownload(task,status,error=false){if(activeDownload!==task)return;clearTimeout(task.fallback);task.controller?.abort();const received=!error&&status==='传输已完成';const batchContinues=received&&task.batchCount>1&&task.batchIndex<task.batchCount;if(!batchContinues)acceptedDownloadBatch=null;task.finished=true;activeDownload=null;syncSendControls();const state=document.getElementById('downloadState');state.textContent=status;state.style.color=error?'var(--red)':(received?'var(--green)':'');document.getElementById('cancelDownload').hidden=true;document.getElementById('openDownload').hidden=!received;downloadTask.classList.remove('visible');downloadTask.style.display='block';downloadTask.classList.toggle('error',error);if(received){rememberReceivedFile(task);if(batchContinues)checkOffer()}else dismissedOfferID=null}
        document.getElementById('openDownload').onclick=()=>{const task=lastDownload;if(!task)return;openStoredFile(receivedFiles.find(item=>item.id===String(task.id))||{id:String(task.id),name:task.name||'文件'})};
        document.getElementById('previewOpen').onclick=()=>{if(previewRecord)openStoredFile(previewRecord)};
        document.getElementById('closePreview').onclick=closePreview;
        filePreview.addEventListener('click',event=>{if(event.target===filePreview)closePreview()});
        async function watchDownload(task){let failures=0;for(let i=0;i<900&&activeDownload===task;i++){await wait(500);if(activeDownload!==task)return;try{const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const progress=await response.json();failures=0;setTask('download',task.label||task.name,progress.status,progress.total?progress.done/progress.total:0);if(!task.pulling&&(progress.status==='传输中'||Number(progress.done)>0)){task.browserStarted=true;clearTimeout(task.fallback)}if(progress.status==='已完成'){clearTimeout(task.fallback);task.serverDone=true;if(!task.pulling)task.browserStarted=true;noteDownloadReady(task);return}if(progress.status==='失败'||progress.status==='已取消'){finishDownload(task,progress.detail||progress.status,true);return}}catch{if(++failures>20){finishDownload(task,'连接中断',true);return}}}if(activeDownload===task)finishDownload(task,'等待超时',true)}
        document.getElementById('cancelDownload').onclick=async()=>{const task=activeDownload;if(!task)return;clearTimeout(task.fallback);task.controller?.abort();acceptedDownloadBatch=null;try{await post('/api/cancel?id='+encodeURIComponent(task.id))}catch{}finishDownload(task,'已取消')};
      </script>
    </body>
    </html>
    """#
}
