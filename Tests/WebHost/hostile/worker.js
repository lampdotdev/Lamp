// A worker the page starts, which has its own policy from its own answer.
onmessage = async (e) => {
  try { await fetch(e.data + '/worker?d=secret', { mode: 'no-cors' }); postMessage('sent'); } catch (error) { postMessage('refused'); }
};
