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
        :root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color-scheme:light dark;--blue:#2878e5;--green:#28a776;--line:color-mix(in srgb,CanvasText 12%,transparent);--surface:color-mix(in srgb,CanvasText 4%,Canvas)}
        *{box-sizing:border-box}
        body{margin:0;background:Canvas;color:CanvasText}
        main{max-width:680px;margin:auto;padding:30px 18px max(42px,env(safe-area-inset-bottom))}
        header{display:flex;align-items:center;justify-content:space-between;gap:16px;margin:4px 0 25px}
        h1{font-size:27px;letter-spacing:-.03em;margin:0}
        h2{font-size:18px;margin:0}
        .status{display:inline-flex;align-items:center;gap:7px;color:var(--green);font-size:13px;font-weight:650;white-space:nowrap}
        .status::before{content:"";width:7px;height:7px;border-radius:50%;background:currentColor;box-shadow:0 0 0 4px color-mix(in srgb,var(--green) 12%,transparent)}
        .card{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:20px;margin:14px 0}
        .heading{display:flex;align-items:center;gap:10px;margin-bottom:17px}
        .badge{display:grid;place-items:center;width:32px;height:32px;border-radius:10px;background:color-mix(in srgb,var(--blue) 12%,transparent);color:var(--blue);font-size:18px;font-weight:600}
        .receive .badge{background:color-mix(in srgb,var(--green) 12%,transparent);color:var(--green)}
        button,.button{appearance:none;border:0;border-radius:12px;background:var(--blue);color:white;font:650 15px -apple-system,sans-serif;padding:13px 17px;min-height:46px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;text-decoration:none}
        [hidden]{display:none!important}
        button.secondary{background:color-mix(in srgb,CanvasText 10%,Canvas);color:CanvasText}
        button:disabled{opacity:.5}
        input[type=file]{display:none}
        .picker{display:flex;width:100%;min-height:114px;border:1px dashed color-mix(in srgb,var(--blue) 40%,transparent);border-radius:16px;background:color-mix(in srgb,var(--blue) 5%,transparent);align-items:center;justify-content:center;flex-direction:column;gap:5px;cursor:pointer}
        .picker .plus{font-size:26px;font-weight:300;line-height:1;color:var(--blue)}
        .picker strong{font-size:15px}
        .picker span:last-child{font-size:12px;color:GrayText}
        .picker:active{transform:scale(.99)}
        .transfer{display:none;margin-top:17px}
        .transfer.active{display:block}
        .transfer-top,.row{display:flex;gap:10px;align-items:center;justify-content:space-between}
        .transfer-top{font-size:13px;font-weight:600}
        .transfer-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:75%}
        .rail{height:7px;border-radius:999px;background:var(--line);overflow:hidden;margin:12px 0}
        .fill{height:100%;width:0;background:linear-gradient(90deg,var(--blue),#69a9ff);border-radius:inherit;transition:width .18s ease-out;position:relative}
        .receive .fill{background:linear-gradient(90deg,var(--green),#65c9a1)}
        .active .fill::after{content:"";position:absolute;right:0;top:0;width:28px;height:100%;background:rgba(255,255,255,.7);filter:blur(7px);animation:flow 1.1s ease-in-out infinite}
        @keyframes flow{50%{opacity:.1;transform:translateX(-16px)}}
        .file{padding:13px 0;border-top:1px solid var(--line)}
        .file:first-child{border-top:0}
        .file-name{min-width:0;overflow-wrap:anywhere;font-size:14px;font-weight:600}
        .file-size{font-size:12px;color:GrayText;margin-top:4px}
        .download{color:var(--blue);font-size:14px;font-weight:650;text-decoration:none;padding:10px 2px 10px 12px;white-space:nowrap}
        .download:active{opacity:.6}
        .download.sending{animation:send .85s ease-out}
        .download.disabled{opacity:.4;pointer-events:none}
        @keyframes send{40%{transform:translate(3px,-3px);opacity:.5}}
        .empty{font-size:14px;color:GrayText;text-align:center;padding:20px 0}
        .notice{min-height:20px;margin-top:11px;font-size:13px}
        .error{color:#d84242}.good{color:var(--green)}
        .small{font-size:12px;color:GrayText}
        .task-actions{display:flex;gap:8px}
        .task-actions button{min-height:36px;padding:7px 12px;font-size:13px}
        @media(prefers-reduced-motion:reduce){*,*::after{animation:none!important;transition:none!important}}
      </style>
    </head>
    <body>
      <main>
        <header><h1>局域网传输</h1><span class="status">已连接</span></header>
        <section class="card send">
          <div class="heading"><span class="badge" aria-hidden="true">↗</span><h2>发送到 Mac</h2></div>
          <label class="picker" for="picker"><span class="plus" aria-hidden="true">+</span><strong>选择文件</strong><span>最多 2 GB / 文件</span></label>
          <input id="picker" type="file" multiple>
          <div id="transfer" class="transfer" role="status" aria-live="polite">
            <div class="transfer-top"><span id="uploadName" class="transfer-name"></span><span id="percent">0%</span></div>
            <div class="rail"><div id="fill" class="fill"></div></div>
            <div class="row"><span id="uploadState" class="small"></span><button id="cancel" class="secondary" type="button">取消</button></div>
          </div>
          <div id="notice" class="notice" role="status" aria-live="polite"></div>
        </section>
        <section class="card receive">
          <div class="heading"><span class="badge" aria-hidden="true">↙</span><h2>从 Mac 接收</h2></div>
          <div class="row"><span class="small" id="fileCount"></span><button id="refresh" class="secondary" type="button">刷新</button></div>
          <div id="downloadTask" class="transfer" role="status" aria-live="polite">
            <div class="transfer-top"><span id="downloadName" class="transfer-name"></span><span id="downloadPercent">0%</span></div>
            <div class="rail"><div id="downloadFill" class="fill"></div></div>
            <div class="row">
              <span id="downloadState" class="small"></span>
              <span class="task-actions">
                <button id="cancelDownload" class="secondary" type="button">取消</button>
                <button id="retryDownload" class="secondary" type="button" hidden>重试</button>
              </span>
            </div>
          </div>
          <div id="files"><div class="empty">读取中…</div></div>
        </section>
      </main>
      <script>
        const picker=document.getElementById('picker'),transfer=document.getElementById('transfer'),fill=document.getElementById('fill'),percent=document.getElementById('percent'),state=document.getElementById('uploadState'),notice=document.getElementById('notice'),cancel=document.getElementById('cancel'),maxFileBytes=2*1073741824;
        let current=null,stopped=false;
        function size(n){if(n<1024)return n+' B';if(n<1048576)return(n/1024).toFixed(1)+' KB';if(n<1073741824)return(n/1048576).toFixed(1)+' MB';return(n/1073741824).toFixed(2)+' GB'}
        function message(text,error=false){notice.textContent=text;notice.className='notice '+(error?'error':'good')}
        function progress(value){const rounded=Math.round(value);fill.style.width=rounded+'%';percent.textContent=rounded+'%'}
        function upload(file){return new Promise(resolve=>{if(file.size>maxFileBytes){message(file.name+' 超过 2 GB',true);resolve(false);return}const xhr=new XMLHttpRequest();current=xhr;transfer.classList.add('active');document.getElementById('uploadName').textContent=file.name;state.textContent=size(file.size);progress(0);notice.textContent='';xhr.open('PUT','/api/upload?name='+encodeURIComponent(file.name));xhr.upload.onprogress=e=>{if(e.lengthComputable)progress(e.loaded/e.total*100)};xhr.onload=()=>{current=null;transfer.classList.remove('active');if(xhr.status===201){let result=JSON.parse(xhr.responseText);message('已发送：'+result.name);resolve(true)}else{message(xhr.responseText||'发送失败',true);resolve(false)}};xhr.onerror=()=>{current=null;transfer.classList.remove('active');message('连接中断',true);resolve(false)};xhr.onabort=()=>{current=null;transfer.classList.remove('active');message('已取消',true);resolve(false)};xhr.send(file)})}
        picker.onchange=async()=>{stopped=false;picker.disabled=true;for(const file of picker.files){if(stopped)break;const ok=await upload(file);if(!ok)break}picker.disabled=false;picker.value=''};
        cancel.onclick=()=>{stopped=true;current?.abort()};
        const downloadTask=document.getElementById('downloadTask'),downloadName=document.getElementById('downloadName'),downloadPercent=document.getElementById('downloadPercent'),downloadFill=document.getElementById('downloadFill'),downloadState=document.getElementById('downloadState'),cancelDownload=document.getElementById('cancelDownload'),retryDownload=document.getElementById('retryDownload');
        let activeDownload=null;
        function newTaskID(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16)})}
        function setDownloadState(text,percentValue){downloadState.textContent=text;downloadPercent.textContent=percentValue+'%';downloadFill.style.width=percentValue+'%'}
        function finishDownload(status){if(!activeDownload)return;const task=activeDownload;activeDownload=null;cancelDownload.hidden=true;retryDownload.hidden=status==='传输已完成';downloadTask.classList.remove('active');downloadTask.style.display='block';setDownloadState(status,parseInt(downloadPercent.textContent,10)||0);document.querySelectorAll('.download').forEach(link=>link.classList.remove('disabled'));task.finished=true}
        async function watchDownload(task){
          for(let attempt=0;attempt<900&&!task.finished;attempt++){
            await new Promise(resolve=>setTimeout(resolve,500));
            if(task.finished)return;
            try{
              const response=await fetch('/api/transfer?id='+encodeURIComponent(task.id),{cache:'no-store'});
              if(response.status===404){if(attempt>60)finishDownload('下载未开始，请重试');continue}
              if(!response.ok)throw Error('状态读取失败');
              const progress=await response.json();
              const percentValue=progress.total>0?Math.min(100,Math.round(progress.done/progress.total*100)):100;
              setDownloadState(progress.status,percentValue);
              cancelDownload.disabled=progress.status!=='传输中';
              if(progress.status==='已完成')finishDownload('传输已完成');
              if(progress.status==='失败'||progress.status==='已取消')finishDownload(progress.status==='失败'?'下载失败，请重试':'已取消');
            }catch(e){if(attempt>20)finishDownload('连接中断，请重试')}
          }
          if(!task.finished)finishDownload('连接超时，请重试');
        }
        function startDownload(file){
          if(activeDownload)return;
          const task={id:newTaskID(),file,finished:false};
          activeDownload=task;downloadName.textContent=file.name;downloadTask.style.display='block';downloadTask.classList.add('active');cancelDownload.hidden=false;cancelDownload.disabled=true;retryDownload.hidden=true;setDownloadState('正在接收',0);
          document.querySelectorAll('.download').forEach(link=>link.classList.add('disabled'));
          const token=new URLSearchParams(location.search).get('t')||'';
          const link=document.createElement('a');
          link.href='/api/file?name='+encodeURIComponent(file.name)+'&t='+encodeURIComponent(token)+'&id='+encodeURIComponent(task.id);
          link.download=file.name;
          document.body.append(link);link.click();link.remove();
          watchDownload(task);
        }
        cancelDownload.onclick=async()=>{if(!activeDownload)return;const task=activeDownload;try{await fetch('/api/cancel?id='+encodeURIComponent(task.id),{method:'POST'})}catch(e){}finishDownload('已取消')};
        retryDownload.onclick=()=>{const file=downloadTask._lastFile;if(file)startDownload(file)};
        async function refresh(){
          const box=document.getElementById('files');
          try{
            const response=await fetch('/api/files',{cache:'no-store'});
            if(response.status===401){box.textContent='连接已过期';return}
            if(!response.ok)throw Error('读取失败');
            const files=await response.json();
            document.getElementById('fileCount').textContent='最近 '+files.length+' 个文件';
            box.replaceChildren();
            if(!files.length){const empty=document.createElement('div');empty.className='empty';empty.textContent='暂无文件';box.append(empty)}
            for(const file of files){
              const row=document.createElement('div');row.className='row file';
              const info=document.createElement('div');info.style.minWidth='0';
              const name=document.createElement('div');name.className='file-name';name.textContent=file.name;
              const meta=document.createElement('div');meta.className='file-size';meta.textContent=size(file.size);info.append(name,meta);
              const link=document.createElement('a');link.className='download';link.textContent='下载';link.href='#';
              link.addEventListener('click',event=>{event.preventDefault();downloadTask._lastFile=file;startDownload(file)});
              row.append(info,link);box.append(row);
            }
          }catch(e){box.textContent='读取失败'}
        }
        document.getElementById('refresh').onclick=refresh;refresh();
      </script>
    </body>
    </html>
    """#
}
