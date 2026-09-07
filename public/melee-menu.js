class UqmMenu extends HTMLElement {
  static observedAttributes = ["data-error", "data-match"];
  attributeChangedCallback(name, before, after) { if (after && after !== before && this.sounds) this.play(name === "data-match" ? 1 : 2); }
  connectedCallback() {
    this.sounds = [1,2,3,4].map(n => { const sound = new Audio(`/sounds/menu-${n}.wav`); sound.volume = .3; return sound; });
    this.key = event => {
      if (this.getAttribute("data-playing") === "true" || event.altKey || event.ctrlKey || event.metaKey) return;
      const active = document.activeElement;
      if (active && active !== document.body && !this.contains(active)) return;
      if (active?.matches("input,select,textarea")) {
        if (event.key === "Escape") { active.blur(); event.stopPropagation(); }
        return;
      }
      if (event.key === "Escape") {
        const back = [...this.querySelectorAll("button,a")].find(e => /^(Back to rooms|Leave online room|Back to hangar|Fleet hangar|Return to hangar)$/.test(e.textContent.trim()));
        if (back) { event.preventDefault(); event.stopPropagation(); back.click(); }
        return;
      }
      if (!event.key.startsWith("Arrow")) return;
      const options = [...this.querySelectorAll("button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled)")].filter(e => {
        const box=e.getBoundingClientRect(); return box.width>0 && box.height>0 && getComputedStyle(e).visibility!=="hidden" && box.bottom>0 && box.top<innerHeight;
      });
      if (!options.length) return;
      event.preventDefault(); event.stopPropagation();
      let next=options[0];
      if (options.includes(active)) {
        const box=active.getBoundingClientRect(), x=box.x+box.width/2, y=box.y+box.height/2;
        const dx=event.key==="ArrowRight"?1:event.key==="ArrowLeft"?-1:0, dy=event.key==="ArrowDown"?1:event.key==="ArrowUp"?-1:0;
        const candidates=options.filter(e=>e!==active).map(e=>{const b=e.getBoundingClientRect(), vx=b.x+b.width/2-x,vy=b.y+b.height/2-y; return {e,along:vx*dx+vy*dy,across:Math.abs(vx*dy-vy*dx)};}).filter(c=>c.along>2).sort((a,b)=>(a.along+a.across*4)-(b.along+b.across*4));
        next=candidates[0]?.e || options[(options.indexOf(active)+(dx+dy>0?1:options.length-1))%options.length];
      }
      next.focus({preventScroll:true}); this.play(0);
    };
    this.click = event => { if (event.target.closest("button,a") && this.getAttribute("data-playing")!=="true") this.play(/^(Back|Leave|Return|Fleet hangar)/.test(event.target.closest("button,a").textContent.trim()) ? 3 : 1); };
    document.addEventListener("keydown",this.key,true);
    this.addEventListener("click",this.click);
  }
  play(index) { if(this.getAttribute("data-muted")==="true") return; const audio=this.sounds[index]; audio.currentTime=0; audio.play().catch(()=>{}); }
  disconnectedCallback() { document.removeEventListener("keydown",this.key,true); this.removeEventListener("click",this.click); this.sounds?.forEach(s=>s.pause()); }
}
if(!customElements.get("uqm-menu"))customElements.define("uqm-menu",UqmMenu);
