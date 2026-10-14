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
        :root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color-scheme:light dark;--blue:#2878e5;--green:#24a875;--line:color-mix(in srgb,CanvasText 12%,transparent);--surface:color-mix(in srgb,CanvasText 4%,Canvas)}
        *{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:Canvas;color:CanvasText}button{font:inherit}
        main{max-width:640px;margin:auto;padding:28px 18px max(42px,env(safe-area-inset-bottom))}
        header{display:flex;align-items:center;justify-content:space-between;margin-bottom:24px}h1{font-size:25px;letter-spacing:-.03em;margin:0}h2{font-size:18px;margin:0}
        .connected{color:var(--green);font-size:13px;font-weight:650}.connected::before{content:"";display:inline-block;width:7px;height:7px;margin-right:7px;border-radius:50%;background:currentColor}
        .card{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:20px;margin:14px 0;min-height:190px}
        .heading{display:flex;align-items:center;gap:10px;margin-bottom:18px}.symbol{display:grid;place-items:center;width:34px;height:34px;border-radius:10px;background:color-mix(in srgb,var(--blue) 13%,transparent);color:var(--blue);font-size:19px}.receive .symbol{background:color-mix(in srgb,var(--green) 13%,transparent);color:var(--green)}
        .pick{display:grid;place-items:center;gap:5px;min-height:116px;border:1px dashed color-mix(in srgb,var(--blue) 45%,transparent);border-radius:16px;background:color-mix(in srgb,var(--blue) 5%,transparent);cursor:pointer}.pick strong{font-size:15px}.pick span{font-size:26px;line-height:1;color:var(--blue)}.pick:active{transform:scale(.99)}input[type=file]{display:none}
        .empty{display:grid;place-items:center;min-height:116px;border:1px dashed var(--line);border-radius:16px;color:GrayText;font-size:14px}.empty.missing{border-color:color-mix(in srgb,#d88a28 55%,transparent);background:color-mix(in srgb,#d88a28 9%,Canvas);color:#c47b20}
        .task{display:none;padding:15px;border-radius:15px;background:color-mix(in srgb,CanvasText 5%,Canvas)}.task.visible{display:block}.task-head,.task-foot{display:flex;align-items:center;justify-content:space-between;gap:12px}.task-head strong{font-size:14px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.task-head span,.task-foot span{color:GrayText;font-size:12px}.task-foot{margin-top:10px}
        .rail{height:7px;border-radius:99px;background:var(--line);overflow:hidden;margin:14px 0}.fill{height:100%;width:0;border-radius:inherit;background:linear-gradient(90deg,var(--blue),#70b3ff);transition:width .2s ease-out}.receive .fill{background:linear-gradient(90deg,var(--green),#75d5ad)}.task.visible .fill::after{content:"";float:right;width:24px;height:100%;background:rgba(255,255,255,.7);filter:blur(5px);animation:flow 1.1s infinite}@keyframes flow{50%{opacity:.1}}
        .button{appearance:none;border:0;border-radius:11px;min-height:39px;padding:8px 15px;font-size:13px;font-weight:650;cursor:pointer;background:var(--blue);color:#fff}.button.secondary{color:CanvasText;background:color-mix(in srgb,CanvasText 10%,Canvas)}.button:disabled{opacity:.45}
        .notice{min-height:20px;margin-top:11px;font-size:13px}.error{color:#d84242}.good{color:var(--green)}
        .scrim{position:fixed;inset:0;display:grid;place-items:center;background:rgba(0,0,0,.48);padding:20px;z-index:10}.scrim[hidden]{display:none}.dialog{width:min(100%,380px);padding:24px;background:Canvas;color:CanvasText;border:1px solid var(--line);border-radius:22px;box-shadow:0 18px 60px rgba(0,0,0,.25)}.dialog-icon{display:grid;place-items:center;width:46px;height:46px;border-radius:14px;background:color-mix(in srgb,var(--green) 13%,transparent);color:var(--green);font-size:25px}.dialog h2{margin:17px 0 10px}.dialog-name{overflow-wrap:anywhere;font-size:14px;font-weight:600}.dialog-size{color:GrayText;font-size:13px;margin-top:5px}.actions{display:flex;gap:10px;margin-top:24px}.actions button{flex:1;min-height:46px;font-size:15px}
        @media(prefers-reduced-motion:reduce){*,*::after{animation:none!important;transition:none!important}}
      </style>
    </head>
    <body>
      <main>
        <header><h1>局域网传输</h1><span class="connected">已连接</span></header>
        <section class="card send">
          <div class="heading"><span class="symbol" aria-hidden="true">↑</span><h2>发送到其他设备</h2></div>
          <label id="pickLabel" class="pick" for="picker"><span aria-hidden="true">+</span><strong>选择文件</strong></label>
          <input id="picker" type="file">
          <div id="uploadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="uploadName"></strong><span id="uploadPercent">0%</span></div>
            <div class="rail"><div id="uploadFill" class="fill"></div></div>
            <div class="task-foot"><span id="uploadState"></span><button id="cancelUpload" class="button secondary" type="button">取消</button></div>
          </div>
          <div id="uploadNotice" class="notice" role="status" aria-live="polite"></div>
        </section>
        <section class="card receive">
          <div class="heading"><span class="symbol" aria-hidden="true">↓</span><h2>从其他设备接收</h2></div>
          <div id="receiveEmpty" class="empty">等待文件</div>
          <div id="downloadTask" class="task" role="status" aria-live="polite">
            <div class="task-head"><strong id="downloadName"></strong><span id="downloadPercent">0%</span></div>
            <div class="rail"><div id="downloadFill" class="fill"></div></div>
            <div class="task-foot"><span id="downloadState"></span><button id="cancelDownload" class="button secondary" type="button">取消</button></div>
          </div>
        </section>
      </main>
      <div id="offerModal" class="scrim" hidden>
        <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="offerTitle">
          <div class="dialog-icon" aria-hidden="true">↙</div><h2 id="offerTitle">接收文件</h2>
          <div id="offerName" class="dialog-name"></div><div id="offerSize" class="dialog-size"></div>
          <div class="actions"><button id="decline" class="button secondary" type="button">取消</button><button id="accept" class="button" type="button">下载</button></div>
        </div>
      </div>
      <script>
        const picker=document.getElementById('picker'),pickLabel=document.getElementById('pickLabel'),uploadTask=document.getElementById('uploadTask'),uploadNotice=document.getElementById('uploadNotice'),downloadTask=document.getElementById('downloadTask'),receiveEmpty=document.getElementById('receiveEmpty'),offerModal=document.getElementById('offerModal');
        const maxFileBytes=2*1073741824;
        let activeUpload=null,activeDownload=null,currentOffer=null,checkingOffer=false,dismissedOfferID=null;
        const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
        function size(n){if(n<1000)return n+' B';if(n<1000000)return Math.round(n/1000)+' KB';if(n<1000000000)return(n/1000000).toFixed(1)+' MB';return(n/1000000000).toFixed(2)+' GB'}
        function setTask(prefix,name,status,ratio){document.getElementById(prefix+'Name').textContent=name;document.getElementById(prefix+'State').textContent=status;const pct=Math.max(0,Math.min(100,Math.round(ratio*100)));document.getElementById(prefix+'Percent').textContent=pct+'%';document.getElementById(prefix+'Fill').style.width=pct+'%'}
        function notice(text,error=false){uploadNotice.textContent=text;uploadNotice.className='notice '+(error?'error':'good')}
        function showUpload(file){uploadTask.classList.add('visible');pickLabel.hidden=true;picker.disabled=true;setTask('upload',file.name,'等待 Mac 接收 · '+size(file.size),0)}
        function finishUpload(text,error=false){activeUpload=null;uploadTask.classList.remove('visible');pickLabel.hidden=false;picker.disabled=false;picker.value='';notice(text,error)}
        async function post(url){return fetch(url,{method:'POST',cache:'no-store'})}
        async function offerUpload(file){
          if(activeUpload||activeDownload||currentOffer){notice('当前有传输任务',true);return}
          if(file.size>maxFileBytes){notice('文件超过 2 GB',true);return}
          const task={id:null,file,xhr:null,finished:false,sending:false};activeUpload=task;showUpload(file);notice('');
          try{const response=await post('/api/offer-upload?name='+encodeURIComponent(file.name)+'&size='+file.size);if(!response.ok)throw Error(response.status===409?'当前有传输任务':'发送失败');const result=await response.json();task.id=result.id;if(activeUpload!==task){await post('/api/cancel?id='+encodeURIComponent(task.id));return}watchUpload(task)}
          catch(error){finishUpload(error.message,true)}
        }
        picker.onchange=()=>{const file=picker.files?.[0];if(file)offerUpload(file)};
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
          if(checkingOffer||activeUpload||activeDownload)return;checkingOffer=true;
          try{const response=await fetch('/api/offer',{cache:'no-store'});if(response.status===204){if(currentOffer){const previous=currentOffer;const state=await fetch('/api/transfer?id='+encodeURIComponent(previous.id),{cache:'no-store'});if(state.ok){const result=await state.json();receiveEmpty.textContent=result.detail||result.status;receiveEmpty.classList.toggle('missing',result.status==='失败')}}currentOffer=null;dismissedOfferID=null;offerModal.hidden=true}else if(response.status===200){const offer=await response.json();if(offer.id!==dismissedOfferID&&!activeUpload&&!activeDownload){currentOffer=offer;receiveEmpty.textContent='等待文件';receiveEmpty.classList.remove('missing');document.getElementById('offerName').textContent=offer.name;document.getElementById('offerSize').textContent=offer.displaySize||size(offer.size);offerModal.hidden=false}}}catch{}finally{checkingOffer=false}
        }
        setInterval(checkOffer,700);checkOffer();
        document.getElementById('decline').onclick=async()=>{const offer=currentOffer;if(!offer)return;currentOffer=null;dismissedOfferID=offer.id;offerModal.hidden=true;try{await post('/api/cancel?id='+encodeURIComponent(offer.id))}catch{}};
        document.getElementById('accept').onclick=()=>{
          const offer=currentOffer;if(!offer)return;currentOffer=null;offerModal.hidden=true;
          const task={id:offer.id,name:offer.name,finished:false};activeDownload=task;receiveEmpty.hidden=true;downloadTask.style.display='';downloadTask.classList.add('visible');downloadTask.classList.remove('error');document.getElementById('cancelDownload').hidden=false;setTask('download',offer.name,'等待系统确认',0);
          const token=new URLSearchParams(location.search).get('t')||'';const link=document.createElement('a');link.href='/api/file?id='+encodeURIComponent(offer.id)+'&t='+encodeURIComponent(token);link.download=offer.name;document.body.append(link);link.click();link.remove();watchDownload(task)
        };
        function finishDownload(task,status,error=false){if(activeDownload!==task)return;task.finished=true;activeDownload=null;document.getElementById('downloadState').textContent=status;document.getElementById('cancelDownload').hidden=true;downloadTask.classList.remove('visible');downloadTask.style.display='block';if(error)downloadTask.classList.add('error')}
        async function watchDownload(task){let failures=0;for(let i=0;i<900&&activeDownload===task;i++){await wait(500);if(activeDownload!==task)return;try{const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});if(!response.ok)throw Error();const progress=await response.json();failures=0;setTask('download',task.name,progress.status,progress.total?progress.done/progress.total:0);if(progress.status==='已完成'){finishDownload(task,'传输已完成');return}if(progress.status==='失败'||progress.status==='已取消'){finishDownload(task,progress.detail||progress.status,true);return}}catch{if(++failures>20){finishDownload(task,'连接中断',true);return}}}if(activeDownload===task)finishDownload(task,'等待超时',true)}
        document.getElementById('cancelDownload').onclick=async()=>{const task=activeDownload;if(!task)return;try{await post('/api/cancel?id='+encodeURIComponent(task.id))}catch{}finishDownload(task,'已取消')};
      </script>
    </body>
    </html>
    """#
}
