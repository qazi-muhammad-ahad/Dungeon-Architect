(function(root) {
  'use strict';
  const options = {types:[{description:'Dungeon Architect project',accept:{'application/json':['.json']}}]};
  class DungeonFiles {
    constructor() {
      this.handle = null; this.candidate = null; this.dirty = false;
      this.beforeUnload = e => { if(this.dirty) {e.preventDefault(); e.returnValue = '';} };
      root.addEventListener('beforeunload',this.beforeUnload);
    }
    async open() {
      this.candidate = null;
      if (root.showOpenFilePicker) {
        const [handle] = await root.showOpenFilePicker({...options,multiple:false});
        const file = await handle.getFile();
        if(file.size > 16777216) throw new Error('Project exceeds 16 MiB.');
        const text = new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer());
        this.candidate = handle;
        return JSON.stringify({name:file.name,text});
      }
      return new Promise((resolve,reject) => {
        const input = document.createElement('input'); input.type = 'file'; input.accept = '.json,application/json';
        input.oncancel = () => {input.remove(); resolve('null');};
        input.onchange = async () => {
          try {
            const file = input.files[0]; if(!file) {resolve('null');return;}
            if(file.size > 16777216) throw new Error('Project exceeds 16 MiB.');
            resolve(JSON.stringify({name:file.name,text:new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer())}));
          } catch(e) {reject(e);} finally {input.remove();}
        };
        input.click();
      });
    }
    adopt() { this.handle = this.candidate; this.candidate = null; }
    reset() { this.handle = null; this.candidate = null; }
    async save(text,name,saveAs) {
      if(root.showSaveFilePicker) {
        // Invoke picker before the first await to retain user activation.
        const handle = saveAs || !this.handle ? await root.showSaveFilePicker({...options,suggestedName:name}) : this.handle;
        let stream;
        try {
          stream = await handle.createWritable();
          await stream.write(text); await stream.close();
          this.handle = handle;
          return JSON.stringify({name:handle.name,download:false});
        } catch(error) { if(stream) await stream.abort().catch(()=>{}); throw error; }
      }
      const url = URL.createObjectURL(new Blob([text],{type:'application/json'}));
      const a = document.createElement('a'); a.href = url; a.download = name; a.click();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
      // A download request does not prove the user saved the file.
      return JSON.stringify({name,download:true});
    }
    setDirty(value) { this.dirty = value; }
    dispose() { root.removeEventListener('beforeunload',this.beforeUnload); }
  }
  root.DungeonFiles = DungeonFiles;
})(globalThis);
