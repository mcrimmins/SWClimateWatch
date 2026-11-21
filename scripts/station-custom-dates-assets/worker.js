importScripts('model.js');
let rows = [], station = null;
self.onmessage = event => {
  const {id, type} = event.data;
  try {
    if (type === 'compute') {
      const started = performance.now();
      rows = []; station = event.data.station;
      rows = StationCustomModel.select(event.data.chunks, event.data.start, event.data.end);
      const summary = StationCustomModel.summarize(rows), bins = StationCustomModel.bins(rows);
      self.postMessage({id, summary, bins, compute_ms: performance.now() - started});
    } else if (type === 'csv') {
      if (!station || !rows.length) throw Error('Select a period before exporting.');
      self.postMessage({id, csv: StationCustomModel.csv(rows, station)});
    }
  } catch (error) { self.postMessage({id, error: error.message}); }
};
