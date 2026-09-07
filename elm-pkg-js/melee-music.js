exports.init = async function () {
// Browser playback only; Elm owns track selection, pause and sound settings.
class UqmMusic extends HTMLElement {
  static observedAttributes = ["src", "playing", "muted", "loop"];
  constructor() {
    super();
    this.audio = new Audio();
    this.audio.volume = 0.35;
    this.audio.preload = "auto";
    this.unlock = () => this.sync();
  }
  connectedCallback() {
    document.addEventListener("pointerdown", this.unlock);
    document.addEventListener("keydown", this.unlock);
    this.sync();
  }
  disconnectedCallback() {
    this.audio.pause();
    document.removeEventListener("pointerdown", this.unlock);
    document.removeEventListener("keydown", this.unlock);
  }
  attributeChangedCallback() { if (this.isConnected) this.sync(); }
  sync() {
    const src = this.getAttribute("src") || "";
    this.audio.muted = this.getAttribute("muted") === "true";
    this.audio.loop = this.getAttribute("loop") === "true";
    if (this.track !== src) {
      this.track = src;
      this.audio.pause();
      if (src) this.audio.src = src;
      else { this.audio.removeAttribute("src"); this.audio.load(); }
    }
    if (src && this.getAttribute("playing") === "true") {
      if (this.audio.paused && !(this.audio.ended && !this.audio.loop)) this.audio.play().catch(() => {});
    } else this.audio.pause();
  }
}
if (!customElements.get("uqm-music")) customElements.define("uqm-music", UqmMusic);

};
