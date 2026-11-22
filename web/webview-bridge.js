/* Injected into WebView pages of Try Before Build: exposes addJavascriptInterface objects synchronously. */
(function(){
  var s=document.currentScript, names=(s&&s.getAttribute('data-b')||'').split(',').filter(Boolean);
  names.forEach(function(n){
    window[n]=new Proxy({}, {get:function(t,m){ if(typeof m!=='string') return undefined;
      return function(){ var a=[].slice.call(arguments); return parent.__apkbBridge(n,m,a); }; }});
  });
  window.addEventListener('error',function(e){ try{parent.__apkbWebLog&&parent.__apkbWebLog('error',e.message+' ('+(e.filename||'').split('/').pop()+':'+e.lineno+')');}catch(_){} });
  ['log','warn','error'].forEach(function(k){var o=console[k];console[k]=function(){try{parent.__apkbWebLog&&parent.__apkbWebLog(k,[].slice.call(arguments).join(' '));}catch(_){} o.apply(console,arguments);};});
})();
