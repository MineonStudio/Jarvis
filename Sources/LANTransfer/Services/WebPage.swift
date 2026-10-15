import Foundation

enum WebPage {
    static let html = #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
      <meta name="color-scheme" content="light dark">
      <title>局域网传输</title>
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
        .rail{height:7px;border-radius:99px;background:var(--line);overflow:hidden;margin:14px 0}.fill{height:100%;width:0;border-radius:inherit;background:linear-gradient(90deg,var(--accent),#70b3ff);transition:width .2s ease-out}.task.visible .fill::after{content:"";float:right;width:24px;height:100%;background:rgba(255,255,255,.7);filter:blur(5px);animation:flow 1.1s infinite}@keyframes flow{50%{opacity:.1}}
        .button{appearance:none;border:0;border-radius:11px;min-height:39px;padding:8px 15px;font-size:13px;font-weight:650;cursor:pointer;background:var(--accent);color:#fff}.button.secondary{color:CanvasText;background:color-mix(in srgb,CanvasText 10%,Canvas)}.button:disabled{opacity:.45}.task-actions{display:flex;gap:8px;flex-wrap:wrap}
        .notice{min-height:20px;margin-top:11px;font-size:13px}.error{color:var(--red)}.good{color:var(--green)}
        .scrim{position:fixed;inset:0;display:grid;place-items:center;background:rgba(0,0,0,.48);padding:20px;z-index:10}.scrim[hidden]{display:none}.dialog{width:min(100%,380px);padding:24px;background:Canvas;color:CanvasText;border:1px solid var(--line);border-radius:22px;box-shadow:0 18px 60px rgba(0,0,0,.25)}.dialog-icon{display:grid;place-items:center;width:46px;height:46px;border-radius:14px;background:color-mix(in srgb,var(--accent) 13%,transparent);color:var(--accent);font-size:25px}.dialog h2{margin:17px 0 10px}.dialog-name{overflow-wrap:anywhere;font-size:14px;font-weight:600}.dialog-size{color:GrayText;font-size:13px;margin-top:5px}.offer-text{max-height:38vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;padding:12px;border-radius:12px;background:var(--surface);font-size:14px;line-height:1.5}.actions{display:flex;gap:10px;margin-top:24px}.actions button{flex:1;min-height:46px;font-size:15px}
        .preview-box{width:min(100%,720px);max-height:min(90vh,840px);display:flex;flex-direction:column;background:Canvas;color:CanvasText;border:1px solid var(--line);border-radius:22px;box-shadow:0 18px 60px rgba(0,0,0,.25);overflow:hidden}.preview-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 16px;border-bottom:1px solid var(--line)}.preview-bar span{font-size:14px;font-weight:650;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.preview-body{min-height:240px;display:grid;place-items:center;padding:16px;overflow:auto}.preview-body img,.preview-body video{max-width:100%;max-height:70vh}.preview-body iframe{width:100%;height:70vh;border:0;background:Canvas}
        @media(prefers-reduced-motion:reduce){*,*::after{animation:none!important;transition:none!important}}
      </style>
    </head>
    <body>
      <main>
        <header><h1>局域网传输 · {{DEVICE_IP}}</h1><span class="connected">已连接</span></header>
        <section class="card send">
          <div class="heading"><span class="symbol" aria-hidden="true">↑</span><h2>发送到 Mac</h2></div>
          <div class="text-composer"><input id="textInput" type="text" maxlength="30000" placeholder="请输入要传输的文本或链接" aria-label="请输入要传输的文本或链接" autocomplete="off"><button id="sendText" class="send-text" type="button" aria-label="发送文本" disabled>↑</button></div>
          <label id="pickLabel" class="pick" for="picker"><strong>选择文件</strong></label>
          <input id="picker" type="file">
        </section>
        <section class="card transfers">
          <div class="heading"><h2>传输列表</h2></div>
          <div id="uploadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="uploadName"></strong><span id="uploadPercent">0%</span></div>
            <div class="rail"><div id="uploadFill" class="fill"></div></div>
            <div class="task-foot"><span id="uploadState"></span><button id="cancelUpload" class="button secondary" type="button">取消</button></div>
          </div>
          <div id="uploadNotice" class="notice" role="status" aria-live="polite"></div>
          <div id="downloadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="downloadName"></strong><span id="downloadPercent">0%</span></div>
            <div class="rail"><div id="downloadFill" class="fill"></div></div>
            <div class="task-foot"><span id="downloadState"></span><div class="task-actions"><button id="cancelDownload" class="button secondary" type="button">取消</button><button id="openDownload" class="button" type="button" hidden>打开</button></div></div>
          </div>
          <div id="downloadNotice" class="notice" role="status" aria-live="polite"></div>
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
          <div class="preview-bar"><span id="previewName"></span><button id="closePreview" class="button secondary" type="button">关闭</button></div>
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
        const maxFileBytes=2*1073741824;
        let activeUpload=null,activeDownload=null,activeTextSend=null,currentOffer=null,checkingOffer=false,dismissedOfferID=null,lastDownload=null,lastPreviewUrl=null;
        const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
        function size(n){if(n<1000)return n+' B';if(n<1000000)return Math.round(n/1000)+' KB';if(n<1000000000)return(n/1000000).toFixed(1)+' MB';return(n/1000000000).toFixed(2)+' GB'}
        function syncSendControls(){const locked=!!(activeUpload||activeDownload||activeTextSend||currentOffer);picker.disabled=locked;textInput.disabled=locked;pickLabel.classList.toggle('disabled',locked);sendTextButton.disabled=locked||!textInput.value.trim()}
        function setTask(prefix,name,status,ratio){document.getElementById(prefix+'Name').textContent=name;document.getElementById(prefix+'State').textContent=status;const pct=Math.max(0,Math.min(100,Math.round(ratio*100)));document.getElementById(prefix+'Percent').textContent=pct+'%';document.getElementById(prefix+'Fill').style.width=pct+'%'}
        function notice(text,error=false){uploadNotice.textContent=text;uploadNotice.className='notice '+(error?'error':'good')}
        function receiveNotice(text,error=false){downloadNotice.textContent=text;downloadNotice.className='notice '+(error?'error':'good')}
        function fileUrl(id,inline=false){const token=new URLSearchParams(location.search).get('t')||'';return '/api/file?id='+encodeURIComponent(id)+'&t='+encodeURIComponent(token)+(inline?'&inline=1':'')}
        function mimeOf(name,fallback){const ext=(name.split('.').pop()||'').toLowerCase();return ({png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',gif:'image/gif',webp:'image/webp',svg:'image/svg+xml',txt:'text/plain',json:'application/json',pdf:'application/pdf',mp4:'video/mp4',mov:'video/quicktime',m4v:'video/mp4'}[ext])||fallback||'application/octet-stream'}
        function hidePreviewMedia(){['previewImage','previewVideo','previewFrame','previewFallback'].forEach(id=>document.getElementById(id).hidden=true);const video=document.getElementById('previewVideo');video.pause();video.removeAttribute('src');video.load();document.getElementById('previewImage').removeAttribute('src');document.getElementById('previewFrame').removeAttribute('src')}
        function closePreview(){filePreview.hidden=true;hidePreviewMedia();if(lastPreviewUrl){URL.revokeObjectURL(lastPreviewUrl);lastPreviewUrl=null}}
        function showUpload(file){uploadTask.classList.add('visible');uploadTask.classList.remove('error');document.getElementById('cancelUpload').hidden=false;pickLabel.hidden=true;picker.disabled=true;setTask('upload',file.name,'等待 Mac 接收 · '+size(file.size),0)}
        function finishUpload(text,error=false){activeUpload=null;document.getElementById('cancelUpload').hidden=true;const status=text==='已取消'?'已取消':(error?'发送失败':'已完成');setTask('upload',document.getElementById('uploadName').textContent,status,error?0:1);uploadTask.classList.add('visible');uploadTask.classList.toggle('error',error);pickLabel.hidden=false;picker.value='';syncSendControls();notice(text,error)}
        async function post(url){return fetch(url,{method:'POST',cache:'no-store'})}
        async function offerUpload(file){
          if(activeUpload||activeDownload||activeTextSend||currentOffer){notice('当前有传输任务',true);return}
          if(file.size>maxFileBytes){notice('文件超过 2 GB',true);return}
          const task={id:null,file,xhr:null,finished:false,sending:false};activeUpload=task;syncSendControls();showUpload(file);notice('');
          try{const response=await post('/api/offer-upload?name='+encodeURIComponent(file.name)+'&size='+file.size);if(!response.ok)throw Error(response.status===409?'当前有传输任务':'发送失败');const result=await response.json();task.id=result.id;if(activeUpload!==task){await post('/api/cancel?id='+encodeURIComponent(task.id));return}watchUpload(task)}
          catch(error){finishUpload(error.message,true)}
        }
        picker.onchange=()=>{const file=picker.files?.[0];if(file)offerUpload(file)};
        textInput.oninput=syncSendControls;
        textInput.onkeydown=event=>{if(event.key==='Enter'&&!event.isComposing){event.preventDefault();sendText()}};
        async function sendText(){
          const text=textInput.value.trim();if(!text||activeUpload||activeDownload||activeTextSend||currentOffer)return;
          const task={id:null,finished:false};activeTextSend=task;syncSendControls();uploadTask.classList.add('visible');uploadTask.classList.remove('error');document.getElementById('cancelUpload').hidden=true;setTask('upload','文本消息','正在发送',0);notice('正在发送文本…');
          try{const response=await fetch('/api/offer-text',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});if(!response.ok)throw Error(response.status===409?'当前有传输任务':'发送失败');task.id=(await response.json()).id;textInput.value='';notice('等待 Mac 确认');watchTextSend(task)}catch(error){activeTextSend=null;setTask('upload','文本消息',error.message||'发送失败',0);uploadTask.classList.add('error');syncSendControls();notice(error.message||'发送失败',true)}
        }
        sendTextButton.onclick=sendText;
        async function watchTextSend(task){for(let i=0;i<600&&activeTextSend===task;i++){await wait(500);try{const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const state=await response.json();if(state.status==='已完成'){activeTextSend=null;setTask('upload','文本消息','已接收',1);syncSendControls();notice('文本已接收');return}if(state.status==='失败'||state.status==='已取消'){activeTextSend=null;setTask('upload','文本消息',state.detail||state.status,0);uploadTask.classList.add('error');syncSendControls();notice(state.detail||state.status,true);return}}catch{}}if(activeTextSend===task){activeTextSend=null;setTask('upload','文本消息','等待超时',0);uploadTask.classList.add('error');syncSendControls();notice('等待超时',true)}}
        function sendUpload(task){
          if(task.sending||task.finished)return;task.sending=true;setTask('upload',task.file.name,'正在发送',0);
          const xhr=new XMLHttpRequest();task.xhr=xhr;
          xhr.open('PUT','/api/upload?name='+encodeURIComponent(task.file.name)+'&id='+encodeURIComponent(task.id));
          xhr.upload.onprogress=e=>{if(e.lengthComputable)setTask('upload',task.file.name,'正在发送',e.loaded/e.total)};
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
          if(checkingOffer||activeUpload||activeDownload||activeTextSend)return;checkingOffer=true;
          try{const response=await fetch('/api/offer',{cache:'no-store'});if(response.status===204){currentOffer=null;dismissedOfferID=null;offerModal.hidden=true;syncSendControls()}else if(response.status===200){const offer=await response.json();if(offer.id!==dismissedOfferID&&!activeUpload&&!activeDownload&&!activeTextSend){currentOffer=offer;syncSendControls();const isText=offer.type==='text';document.getElementById('offerIcon').hidden=isText;document.getElementById('offerTitle').textContent=isText?'来自 Mac 的文本':'接收文件';document.getElementById('offerName').textContent=offer.name;document.getElementById('offerName').hidden=isText;document.getElementById('offerSize').textContent=offer.displaySize||size(offer.size);document.getElementById('offerSize').hidden=isText;const text=document.getElementById('offerText');text.textContent=isText?offer.text:'';text.hidden=!isText;document.getElementById('accept').textContent=isText?'复制':'下载';offerModal.hidden=false}}}catch{}finally{checkingOffer=false}
        }
        setInterval(checkOffer,700);checkOffer();
        document.getElementById('decline').onclick=async()=>{const offer=currentOffer;if(!offer)return;currentOffer=null;dismissedOfferID=offer.id;offerModal.hidden=true;syncSendControls();try{await post('/api/cancel?id='+encodeURIComponent(offer.id))}catch{}};
        document.getElementById('accept').onclick=async()=>{
          const offer=currentOffer;if(!offer)return;currentOffer=null;offerModal.hidden=true;
          if(offer.type==='text'){
            try{if(navigator.clipboard?.writeText)await navigator.clipboard.writeText(offer.text);else{const field=document.createElement('textarea');field.value=offer.text;document.body.append(field);field.select();document.execCommand('copy');field.remove()}await post('/api/accept-text?id='+encodeURIComponent(offer.id));setTask('download','文本消息','已复制到剪贴板',1);downloadTask.classList.add('visible');downloadTask.classList.remove('error');document.getElementById('cancelDownload').hidden=true;document.getElementById('openDownload').hidden=true;receiveNotice('')}catch{setTask('download','文本消息','复制失败',0);downloadTask.classList.add('visible','error');document.getElementById('cancelDownload').hidden=true;document.getElementById('openDownload').hidden=true;receiveNotice('复制失败',true)}
            syncSendControls();return
          }
          const task={id:offer.id,name:offer.name,finished:false};activeDownload=task;syncSendControls();lastDownload=task;downloadTask.style.display='';downloadTask.classList.add('visible');downloadTask.classList.remove('error');document.getElementById('cancelDownload').hidden=false;document.getElementById('openDownload').hidden=true;receiveNotice('');setTask('download',offer.name,'等待系统确认',0);
          const link=document.createElement('a');link.href=fileUrl(offer.id);link.download=offer.name;document.body.append(link);link.click();link.remove();watchDownload(task)
        };
        function finishDownload(task,status,error=false){if(activeDownload!==task)return;task.finished=true;activeDownload=null;syncSendControls();const state=document.getElementById('downloadState');state.textContent=status;state.style.color=error?'var(--red)':status==='传输已完成'?'var(--green)':'';document.getElementById('cancelDownload').hidden=true;document.getElementById('openDownload').hidden=!!error;downloadTask.classList.remove('visible');downloadTask.style.display='block';if(error)downloadTask.classList.add('error')}
        document.getElementById('openDownload').onclick=async()=>{
          const task=lastDownload;if(!task)return;
          try{
            const response=await fetch(fileUrl(task.id,true),{cache:'no-store'});if(!response.ok)throw Error('无法打开文件');
            const blob=await response.blob();const type=blob.type&&blob.type!=='application/octet-stream'?blob.type:mimeOf(task.name);
            const typed=blob.type===type?blob:new Blob([blob],{type});
            if(lastPreviewUrl)URL.revokeObjectURL(lastPreviewUrl);
            lastPreviewUrl=URL.createObjectURL(typed);
            hidePreviewMedia();
            document.getElementById('previewName').textContent=task.name;
            if(type.startsWith('image/')){const img=document.getElementById('previewImage');img.src=lastPreviewUrl;img.hidden=false}
            else if(type.startsWith('video/')||type.startsWith('audio/')){const media=document.getElementById('previewVideo');media.src=lastPreviewUrl;media.hidden=false}
            else if(type==='application/pdf'||type.startsWith('text/')){const frame=document.getElementById('previewFrame');frame.src=lastPreviewUrl;frame.hidden=false}
            else {document.getElementById('previewFallback').hidden=false;window.open(lastPreviewUrl,'_blank')}
            filePreview.hidden=false;receiveNotice('')
          }catch(error){receiveNotice(error.message||'打开失败',true)}
        }
        document.getElementById('closePreview').onclick=closePreview;
        filePreview.addEventListener('click',event=>{if(event.target===filePreview)closePreview()});
        async function watchDownload(task){let failures=0;for(let i=0;i<900&&activeDownload===task;i++){await wait(500);if(activeDownload!==task)return;try{const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const progress=await response.json();failures=0;setTask('download',task.name,progress.status,progress.total?progress.done/progress.total:0);if(progress.status==='已完成'){finishDownload(task,'传输已完成');return}if(progress.status==='失败'||progress.status==='已取消'){finishDownload(task,progress.detail||progress.status,true);return}}catch{if(++failures>20){finishDownload(task,'连接中断',true);return}}}if(activeDownload===task)finishDownload(task,'等待超时',true)}
        document.getElementById('cancelDownload').onclick=async()=>{const task=activeDownload;if(!task)return;try{await post('/api/cancel?id='+encodeURIComponent(task.id))}catch{}finishDownload(task,'已取消')};
      </script>
    </body>
    </html>
    """#
}
