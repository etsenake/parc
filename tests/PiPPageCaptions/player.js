function playCaptions(show, clock) {
  const params = new URLSearchParams(location.search);
  if (params.has('render')) {
    document.documentElement.classList.add('render');
    show(params.get('render'));
    return;
  }
  const lines = ['I never asked for this.', '', 'Neither did I.', '',
                 'Then why are we here?', ''];
  let step = 0;
  show(lines[0]);
  setInterval(() => show(lines[++step % lines.length]), 2000);
  let second = 0;
  setInterval(() => { clock.textContent = `0:${String(++second % 60).padStart(2, '0')}`; }, 1000);
}
