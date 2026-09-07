/* elm-pkg-js
import Json.Encode
port melee_browser_to_js : Json.Encode.Value -> Cmd msg
port melee_browser_from_js : (Json.Encode.Value -> msg) -> Sub msg
*/
exports.init = async function(app) {
  window.__uqmBrowserDispose?.();
  const send = value => app.ports.melee_browser_from_js?.send(value);
  const ids = new WeakMap(); let serial=0;
  const identify = element => { if (!element) return ""; if (!ids.has(element)) { ids.set(element, String(++serial)); element.dataset.meleeFocus=ids.get(element); } return ids.get(element); };
  const describe = element => { const r=element.getBoundingClientRect(); return {id:identify(element),label:element.getAttribute("aria-label")||element.textContent.trim(),x:r.x+r.width/2,y:r.y+r.height/2}; };
  const channels = new Map();
  const onCommand = command => {
    const target = command.id ? document.querySelector(`[data-melee-focus="${CSS.escape(command.id)}"]`) : null;
    switch(command.op) {
      case "focus": target?.focus({preventScroll:true}); break;
      case "activate": target?.click(); break;
      case "blur": document.activeElement?.blur(); break;
      case "stop": channels.get(command.channel)?.pause(); break;
      case "play": {
        channels.get(command.channel)?.pause();
        const audio=new Audio(command.src); audio.volume=command.volume;
        channels.set(command.channel,audio); audio.play().catch(()=>{}); break;
      }
    }
  };
  app.ports.melee_browser_to_js?.subscribe(onCommand);
  const onKey = event => {
    const root=document.getElementById("melee-game"), active=document.activeElement;
    if (!root || root.dataset.playing==="true" || event.altKey || event.ctrlKey || event.metaKey || (active!==document.body && !root.contains(active))) return;
    const editing=!!active?.matches("input,select,textarea");
    if ((!event.key.startsWith("Arrow") && event.key!=="Escape") || (editing && event.key!=="Escape")) return;
    event.preventDefault();event.stopPropagation();
    const nodes=[...root.querySelectorAll("button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled)")].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&getComputedStyle(e).visibility!=="hidden";}).map(describe);
    send({event:"key",key:event.key,active:identify(active),editing,nodes});
  };
  const onClick = event => {
    const root=document.getElementById("melee-game"),target=event.target.closest("button,a");
    if (root && target && root.contains(target) && root.dataset.playing!=="true") send({event:"click",label:target.getAttribute("aria-label")||target.textContent.trim()});
  };
  document.addEventListener("keydown",onKey,true);
  document.addEventListener("click",onClick);
  window.__uqmBrowserDispose = () => {
    document.removeEventListener("keydown",onKey,true);
    document.removeEventListener("click",onClick);
    app.ports.melee_browser_to_js?.unsubscribe(onCommand);
    channels.forEach(audio=>audio.pause());
  };
};
