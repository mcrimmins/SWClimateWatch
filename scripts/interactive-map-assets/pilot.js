/* Native-cell queries and nearest-cell display. No climate requests or interpolation. */
(function (root) {
  'use strict';
  const tempColors = ['#081d58','#313695','#4575b4','#91bfdb','#f7f7f7','#fdae61','#d73027','#7f0000','#542788'];
  const tempLabels = ['Record cold (incl. ties)','≤2: near-record cold','2–10: very cold','10–33: cool','33–67: near middle','67–90: warm','90–98: very warm','>98: near-record warm','Record warm (incl. ties)'];
  const rainColors = ['#f7fbff','#deebf7','#c6dbef','#9ecae1','#6baed6','#3182bd','#08519c','#54278f'];
  const rainLabels = ['0–0.1 in.','>0.1–0.5 in.','>0.5–1 in.','>1–2 in.','>2–4 in.','>4–8 in.','>8–12 in.','>12 in.'];
  const spiColors = ['#8c510a','#bf812d','#dfc27d','#f5f5f5','#80cdc1','#35978f','#01665e','#bdbdbd'];
  const spiLabels = ['≤−2: extremely dry','>−2 to −1.5: severely dry','>−1.5 to −1: moderately dry','>−1 to <1: near middle','1 to <1.5: moderately wet','1.5 to <2: very wet','≥2: extremely wet','No supported estimate'];
  const wetColors=['#543005','#8c510a','#bf812d','#dfc27d','#f5f5f5','#80cdc1','#35978f','#01665e','#253494'];
  const wetLabels=['Record dry (incl. ties)','≤2: near-record dry','2–10: very dry','10–33: dry','33–67: near middle','67–90: wet','90–98: very wet','>98: near-record wet','Record wet (incl. ties)'];
  const styles={
    'precipitation-total':{kind:'binned',field:'total_precipitation_inches',title:'Precipitation total',bounds:[.1,.5,1,2,4,8,12,20,30,40,Infinity],colors:[...rainColors.slice(0,7),'#807dba','#6a51a3','#54278f','#3f007d'],labels:[...rainLabels.slice(0,7),'>12–20 in.','>20–30 in.','>30–40 in.','>40 in.']},
    'precipitation-ranking':{kind:'rank',field:'percentile',title:'Precipitation ranking',colors:wetColors,labels:wetLabels},
    'temperature-ranking':{kind:'rank',field:'percentile',title:'Temperature ranking',colors:tempColors,labels:tempLabels},
    'temperature-mean':{kind:'binned',field:'mean_temperature_f',title:'Mean temperature',bounds:[0,20,32,40,50,60,70,80,90,100,Infinity],colors:['#313695','#4575b4','#74add1','#abd9e9','#e0f3f8','#ffffbf','#fee090','#fdae61','#f46d43','#d73027','#7f0000'],labels:['≤0 °F','>0–20 °F','>20–32 °F','>32–40 °F','>40–50 °F','>50–60 °F','>60–70 °F','>70–80 °F','>80–90 °F','>90–100 °F','>100 °F']},
    'temperature-departure':{kind:'binned',field:'departure_f',title:'Temperature departure',bounds:[-10,-6,-3,-1,1,3,6,10,Infinity],colors:['#313695','#4575b4','#74add1','#abd9e9','#f7f7f7','#fdae61','#f46d43','#d73027','#7f0000'],labels:['≤−10 °F','>−10 to −6 °F','>−6 to −3 °F','>−3 to −1 °F','>−1 to +1 °F','>+1 to +3 °F','>+3 to +6 °F','>+6 to +10 °F','>+10 °F']},
    'precipitation-departure':{kind:'binned',field:'departure_inches',title:'Precipitation departure',bounds:[-8,-4,-2,-1,-.25,.25,1,2,4,8,Infinity],colors:['#543005','#8c510a','#bf812d','#dfc27d','#f6e8c3','#f5f5f5','#c7eae5','#80cdc1','#35978f','#01665e','#003c30'],labels:['≤−8 in.','>−8 to −4 in.','>−4 to −2 in.','>−2 to −1 in.','>−1 to −0.25 in.','>−0.25 to +0.25 in.','>+0.25 to +1 in.','>+1 to +2 in.','>+2 to +4 in.','>+4 to +8 in.','>+8 in.']},
    'precipitation-spi':{kind:'spi',field:'spi',title:'Standardized Precipitation Index',colors:spiColors,labels:spiLabels}
  };
  const dailyTemperature={bounds:[0,20,32,50,70,90,100,110,Infinity],colors:['#4a3182','#466db0','#8cb9d3','#c4e2da','#f3efc3','#f6cb7d','#e9934e','#cb5033','#892225'],labels:['≤0 °F','>0–20 °F','>20–32 °F','>32–50 °F','>50–70 °F','>70–90 °F','>90–100 °F','>100–110 °F','>110 °F']};
  const dailyDeparture={bounds:[-20,-10,-5,-2,2,5,10,20,Infinity],colors:['#253494','#2c7fb8','#7fcdbb','#c7e9e3','#f5f3ef','#fee8b4','#fdb163','#df633b','#a32424'],labels:['≤−20 °F','>−20 to −10 °F','>−10 to −5 °F','>−5 to −2 °F','>−2 to +2 °F','>+2 to +5 °F','>+5 to +10 °F','>+10 to +20 °F','>+20 °F']};
  styles['daily-precipitation-total']={daily:true,kind:'binned',field:'observed',title:'Daily precipitation',bounds:[0,.01,.05,.1,.25,.5,1,1.5,2,3,Infinity],colors:['#f5f3ef','#edf5f7','#dcecf1','#c1dfe9','#a9d4e2','#68b6c8','#2f8d9c','#427845','#2b562f','#8d659b','#572968'],labels:['0 in.','>0–0.01 in.','>0.01–0.05 in.','>0.05–0.10 in.','>0.10–0.25 in.','>0.25–0.50 in.','>0.50–1 in.','>1–1.5 in.','>1.5–2 in.','>2–3 in.','>3 in.']};
  for(const metric of ['mean','high','low']){
    styles[`daily-temperature-${metric}`]={...dailyTemperature,daily:true,kind:'binned',field:'observed',title:`Daily ${metric} temperature`};
    styles[`daily-temperature-${metric}_departure`]={...dailyDeparture,daily:true,kind:'binned',field:'departure',title:`Daily ${metric} departure`};
  }
  styles['current-precipitation-total']={...styles['precipitation-total'],current:true,field:'value'};
  styles['current-temperature-mean']={...styles['temperature-mean'],current:true,field:'value'};
  styles['current-temperature-departure']={...styles['temperature-departure'],current:true,field:'value'};
  for(const variable of ['precipitation','temperature']){
    const wet=variable==='precipitation';
    styles[`current-${variable}-ranking`]={current:true,kind:'binned',field:'value',title:`${wet?'Precipitation':'Temperature'} percentile rank`,bounds:[2,10,33,67,90,98,100],
      colors:wet?wetColors.slice(1,8):tempColors.slice(1,8),labels:wet?['≤2: exceptionally dry','>2–10: very dry','>10–33: dry','>33–67: near middle','>67–90: wet','>90–98: very wet','>98: exceptionally wet']:['≤2: exceptionally cold','>2–10: very cold','>10–33: cool','>33–67: near middle','>67–90: warm','>90–98: very warm','>98: exceptionally warm']};
  }
  styles['current-precipitation-percent_normal']={current:true,kind:'binned',field:'value',title:'Precipitation percent of normal',bounds:[25,50,75,90,110,125,150,200,300,Infinity],
    colors:['#543005','#8c510a','#bf812d','#dfc27d','#f5f5f5','#c7eae5','#80cdc1','#35978f','#01665e','#003c30'],labels:['≤25%','>25–50%','>50–75%','>75–90%','>90–110%','>110–125%','>125–150%','>150–200%','>200–300%','>300%']};
  styles['current-precipitation-change']={current:true,kind:'binned',field:'value',title:'Change in 30-day precipitation percentile',bounds:[-50,-30,-10,-5,5,10,30,50,100],colors:['#543005','#8c510a','#bf812d','#dfc27d','#f5f5f5','#80cdc1','#35978f','#01665e','#003c30'],labels:['≤−50 points','>−50 to −30 points','>−30 to −10 points','>−10 to −5 points','>−5 to +5 points','>+5 to +10 points','>+10 to +30 points','>+30 to +50 points','>+50 points']};
  styles['current-precipitation-length']={current:true,kind:'binned',field:'value',title:'Dry-spell length',bounds:[0,7,14,30,60,90,Infinity],colors:['#f5f5f5','#ffffd4','#fee391','#fec44f','#fe9929','#d95f0e','#993404'],labels:['0 days','1–7 days','8–14 days','15–30 days','31–60 days','61–90 days','>90 days']};
  styles['current-dry-spell-ranking']={current:true,kind:'binned',field:'value',title:'Dry-spell percentile rank',bounds:[2,10,33,67,90,98,100],colors:wetColors.slice(1,8).reverse(),labels:['≤2: exceptionally short','>2–10: very short','>10–33: short','>33–67: near middle','>67–90: long','>90–98: very long','>98: exceptionally long']};
  const countColors=['#f7fbff','#deebf7','#c6dbef','#9ecae1','#6baed6','#3182bd','#08519c'];
  styles['current-temperature-count']={current:true,kind:'binned',field:'value',title:'Day/night count',bounds:[0,1,3,7,14,21,30],colors:countColors,labels:['0','1','2–3','4–7','8–14','15–21','22–30']};
  styles['current-temperature-anomaly']={current:true,kind:'binned',field:'value',title:'Freeze-night count anomaly',bounds:[-10,-5,-2,-.5,.5,2,5,10,Infinity],colors:['#7f0000','#d73027','#fdae61','#fee090','#f7f7f7','#abd9e9','#74add1','#4575b4','#313695'],labels:['≤−10 nights','>−10 to −5 nights','>−5 to −2 nights','>−2 to −0.5 nights','>−0.5 to +0.5 nights','>+0.5 to +2 nights','>+2 to +5 nights','>+5 to +10 nights','>+10 nights']};
  styles['current-precipitation-count']={current:true,kind:'binned',field:'value',title:'Wet-day count',bounds:[0,7,14,30,45,60,90],colors:countColors,labels:['0 days','1–7 days','8–14 days','15–30 days','31–45 days','46–60 days','61–90 days']};
  styles['current-precipitation-intensity']={current:true,kind:'binned',field:'value',title:'Precipitation per wet day',bounds:[.1,.25,.5,.75,1,2,Infinity],colors:countColors,labels:['≤0.10 in./wet day','>0.10–0.25','>0.25–0.50','>0.50–0.75','>0.75–1','>1–2','>2 in./wet day']};
  styles['current-precipitation-share']={current:true,kind:'binned',field:'value',title:'Share of precipitation',bounds:[0,10,25,50,75,90,100],colors:['#f7fcfd','#e0ecf4','#bfd3e6','#9ebcda','#8c96c6','#8856a7','#810f7c'],labels:['0%','>0–10%','>10–25%','>25–50%','>50–75%','>75–90%','>90–100%']};
  styles['current-precipitation-maximum']={...styles['current-precipitation-total'],title:'Maximum 3-day precipitation'};
  styles['current-rain-character-ranking']={current:true,kind:'binned',field:'value',title:'Historical percentile',bounds:[2,10,33,67,90,98,100],colors:['#f1eef6','#d7b5d8','#df65b0','#f7f7f7','#74a9cf','#2b8cbe','#045a8d'],labels:['≤2: exceptionally low','>2–10: very low','>10–33: low','>33–67: near middle','>67–90: high','>90–98: very high','>98: exceptionally high']};
  function styleFor(selection){
    if(selection.frequency==='current'&&['dry_spell','longest_dry_spell'].includes(selection.measure)&&selection.metric==='ranking')return styles['current-dry-spell-ranking'];
    if(selection.frequency==='current'&&['wet_frequency','wet_intensity','very_wet_share','wy_extremes'].includes(selection.measure)&&selection.metric==='ranking')return styles['current-rain-character-ranking'];
    if(selection.frequency==='current'&&selection.measure==='warm_days')return {...styles['current-temperature-count'],colors:['#fff5eb','#fee6ce','#fdd0a2','#fdae6b','#fd8d3c','#e6550d','#a63603']};
    return styles[(selection.frequency==='monthly'?'':selection.frequency+'-')+selection.variable+'-'+selection.metric];
  }
  function shiftDate(date,days){
    if(typeof date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(date))throw Error('Choose a valid daily date.');
    const d=new Date(date+'T00:00:00Z');
    if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==date)throw Error('Choose a valid daily date.');
    d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10);
  }
  function displayDate(date){return new Intl.DateTimeFormat('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'}).format(new Date(date+'T00:00:00Z'));}
  function resolveSelection(manifest,requested={}){
    if(requested.frequency==='current'){
      const current=manifest.current;
      if(!current)throw Error('Current Conditions has not been prepared. Rebuild the local viewer.');
      const variable=current.variables[requested.variable]?requested.variable:Object.keys(current.variables)[0];
      const measures=current.variables[variable].measures;
      const measure=measures[requested.measure]?requested.measure:Object.keys(measures)[0];
      const metrics=measures[measure].metrics;
      const metric=metrics[requested.metric]?requested.metric:Object.keys(metrics)[0];
      const periods=measures[measure].periods[metric];
      const period=periods[requested.period]?requested.period:Object.keys(periods)[0];
      const product=Object.keys(current.products).find(id=>{const p=current.products[id];return p.variable===variable&&p.measure===measure&&p.metric===metric&&p.period===period;});
      if(!product)throw Error('Unsupported Current Conditions combination.');
      const id=`current-${product}`,descriptor=current.products[product];
      return {frequency:'current',variable,measure,metric,period,product,id,available:!!manifest.layers[id]&&descriptor.available};
    }
    if(requested.frequency==='daily'){
      const daily=manifest.daily;
      if(!daily)throw Error('Daily cache has not been prepared. Rebuild the local viewer.');
      const variable=daily.variables[requested.variable]?requested.variable:Object.keys(daily.variables)[0];
      const metrics=daily.variables[variable].metrics;
      const metric=metrics[requested.metric]?requested.metric:Object.keys(metrics)[0];
      const date=shiftDate(requested.date===undefined?daily.latest_date:requested.date,0);
      if(date<daily.first_date||date>daily.latest_date)throw Error(`Daily date must be between ${daily.first_date} and ${daily.latest_date}.`);
      const family=variable==='precipitation'?'pcpn':metric.startsWith('high')?'maxt':metric.startsWith('low')?'mint':'tmean';
      const id=`daily-${family}-${date}`,layer=manifest.layers[id];
      const available=!!layer&&(!metric.endsWith('_departure')||layer.normal_available);
      return {frequency:'daily',variable,metric,date,id,available};
    }
    const variable=manifest.variables[requested.variable]?requested.variable:Object.keys(manifest.variables)[0];
    const metrics=manifest.variables[variable].metrics;
    const metric=metrics[requested.metric]?requested.metric:Object.keys(metrics)[0];
    const duration=manifest.durations.includes(Number(requested.duration))?Number(requested.duration):manifest.durations[0];
    const family=metric==='spi'?'spi':variable;
    const id=`${family}-${String(duration).padStart(2,'0')}month`;
    if(!manifest.layers[id])throw Error('This monthly combination is unavailable.');
    return {frequency:'monthly',variable,metric,duration,id,available:true};
  }
  const statuses = ['OK','Insufficient history','Too few positive totals','Too many zero totals','Constant positive totals','Gamma fit failed','Current total missing or invalid','Gamma CDF mismatch'];
  function cellAt(g, lat, lng) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || lng < g.west || lng >= g.east || lat <= g.south || lat > g.north) return -1;
    const row = Math.floor((g.north-lat)/g.dy), col = Math.floor((lng-g.west)/g.dx);
    return row >= 0 && row < g.rows && col >= 0 && col < g.cols ? row*g.cols+col : -1;
  }
  function decode(buffer, layer) {
    if (buffer.byteLength !== layer.bytes) throw new Error('Unexpected climate data length. Rebuild the local pilot.');
    const view = new DataView(buffer), n = layer.grid.rows*layer.grid.cols, data = {};
    for (const [name, f] of Object.entries(layer.fields)) {
      const arr = f.type==='float64'?new Float64Array(n):new Float32Array(n), size = f.type==='float64'?8:f.type === 'float32' ? 4 : f.type === 'uint16' ? 2 : 1;
      for (let i=0;i<n;i++) {
        const o=f.offset+i*size;
        let v=f.type==='float64'?view.getFloat64(o,true):f.type==='float32'?view.getFloat32(o,true):f.type==='uint16'?view.getUint16(o,true):view.getUint8(o);
        if (!['float32','float64'].includes(f.type) && v===(f.type==='uint16'?65535:255)) v=NaN;
        arr[i]=v;
      }
      data[name]=arr;
    }
    if(layer.derived_departure)data.departure=Float64Array.from(data.observed,(v,i)=>v-data.normal[i]);
    return data;
  }
  function category(style, d, i) {
    if (i < 0) return -1;
    if (style.kind === 'binned') {
      const v=d[style.field][i];
      return Number.isFinite(v)?style.bounds.findIndex(x=>v<=x):-1;
    }
    if (style.kind === 'rank') {
      const v=d.percentile[i], rec=d.record[i];
      if (!Number.isFinite(v)) return -1;
      if (rec===1||rec===2) return 8;
      if (rec===3||rec===4) return 0;
      return 1+[2,10,33,67,90,98,100].findIndex(x=>v<=x);
    }
    const v=d.spi[i];
    if (!Number.isFinite(v)) return Number.isFinite(d.spi_status[i])?7:-1;
    return v<=-2?0:v<=-1.5?1:v<=-1?2:v<1?3:v<1.5?4:v<2?5:6;
  }
  const fmt=(v,n=2)=>Number.isFinite(v)?v.toFixed(n):'Unavailable';
  // Companion statistics must describe the identical window, never a nearby release.
  function companions(manifest,selection,layer){
    if(selection.frequency==='current')return Object.entries(manifest.current.products)
      .filter(([id,p])=>p.available&&p.variable===selection.variable&&p.measure===selection.measure&&p.period===selection.period&&`current-${id}`!==selection.id)
      .map(([id,p])=>({id:`current-${id}`,metric:p.metric}))
      .filter(p=>{const l=manifest.layers[p.id];return l&&l.date===layer.date&&l.start_date===layer.start_date;});
    if(selection.frequency==='monthly'&&selection.metric==='spi'){
      const id=`precipitation-${String(selection.duration).padStart(2,'0')}month`,l=manifest.layers[id];
      if(l&&l.period===layer.period)return [{id}];
    }
    return [];
  }
  function pointStats(selection,data,i,context={}){
    const temperature=selection.variable==='temperature',rows=[];
    const unit=(v,suffix,n=2)=>Number.isFinite(v)?`${fmt(v,n)} ${suffix}`:'Unavailable';
    const departure=(v,suffix,n)=>Number.isFinite(v)?`${v>0?'+':''}${fmt(v,n)} ${suffix}`:'Unavailable';
    let note='',reference='';
    if(selection.frequency==='current'){
      const values={...context,[selection.metric]:data.value[i]};
      const valueMetric=temperature?'mean':'total';
      const temperatureLabel=selection.measure==='high'?'Mean high temperature':selection.measure==='low'?'Mean low temperature':'Mean temperature';
      if(valueMetric in values)rows.push([temperature?temperatureLabel:'Total precipitation',unit(values[valueMetric],temperature?'°F':'in.',temperature?1:2)]);
      if('length' in values)rows.push([selection.measure==='longest_dry_spell'?'Longest dry spell':'Current dry spell',unit(values.length,values.length===1?'day':'days',0)]);
      const countLabel=selection.measure==='warm_days'?'Unusually warm days':selection.measure==='cold_nights'?'Unusually cold nights':selection.measure==='freeze_nights'?'Freeze nights':'Wet days';
      const night=['cold_nights','freeze_nights'].includes(selection.measure);
      if('count' in values)rows.push([countLabel,unit(values.count,night?(values.count===1?'night':'nights'):(values.count===1?'day':'days'),0)]);
      if('anomaly' in values)rows.push(['Departure from normal count',departure(values.anomaly,'nights',1)]);
      if('intensity' in values)rows.push(['Mean precipitation per wet day',unit(values.intensity,'in.',2)]);
      if('maximum' in values)rows.push(['Maximum 3-day precipitation',unit(values.maximum,'in.',2)]);
      if('share' in values)rows.push([selection.measure==='wy_extremes'?'Share from maximum 3-day period':'Share from very wet days',unit(values.share,'%',1)]);
      if('departure' in values)rows.push(['Departure from normal',departure(values.departure,'°F',1)]);
      if('percent_normal' in values)rows.push(['Percent of normal',unit(values.percent_normal,'%',1)]);
      if('ranking' in values)rows.push(['Historical percentile',fmt(values.ranking,1)]);
      if('change' in values)rows.push(['14-day change in 30-day percentile',departure(values.change,'points',1)]);
      reference='Comparisons: 1991–2020. Rank and sample size are not available in these Current Maps grids.';
      if(['dry_spell','longest_dry_spell'].includes(selection.measure))reference+=' Dry day: less than 0.04 inch. Higher percentiles mean longer dry spells.';
      if(selection.measure==='rank_change')reference+=' Positive change indicates relative wetting; negative change indicates relative drying.';
      if(selection.measure==='warm_days')reference+=' Days with highs above the local calendar-day 90th percentile.';
      if(selection.measure==='cold_nights')reference+=' Nights with lows below the local calendar-day 10th percentile.';
      if(selection.measure==='freeze_nights')reference+=' Freeze: minimum temperature at or below 32 °F. Positive anomaly means more freeze nights.';
      if(['wet_frequency','wet_intensity'].includes(selection.measure))reference+=' Wet day: at least 0.04 inch. Intensity excludes dry days; no qualifying wet days means unavailable.';
      if(selection.measure==='very_wet_share')reference+=' Very wet days exceed the local wet-day 95th percentile; shares are withheld below 0.10 inch total.';
      if(selection.measure==='wy_extremes')reference+=' Largest complete 3-day total since October 1. Its share is withheld below 0.10 inch water-year precipitation.';
    }else if(selection.frequency==='daily'){
      const metric=selection.metric.split('_')[0];
      rows.push([temperature?`${metric==='mean'?'Mean':metric==='high'?'High':'Low'} temperature`:'Total precipitation',unit(data.observed[i],temperature?'°F':'in.',temperature?1:2)]);
      if(temperature)rows.push(['Reference temperature',unit(data.normal[i],'°F',1)],['Departure from normal',departure(data.departure[i],'°F',1)]);
      reference=temperature?'Reference: 1991–2020, centered five-day calendar window.':'Daily precipitation total; historical comparisons are not available in this view.';
    }else{
      const climate=selection.metric==='spi'?context:data;
      if(climate.percentile){
        rows.push([temperature?'Mean temperature':'Total precipitation',unit(climate[temperature?'mean_temperature_f':'total_precipitation_inches'][i],temperature?'°F':'in.',temperature?1:2)]);
        rows.push(['Departure from normal',departure(climate[temperature?'departure_f':'departure_inches'][i],temperature?'°F':'in.',temperature?1:2)]);
        rows.push(['Historical percentile',fmt(climate.percentile[i],1)]);
        const rank=climate[temperature?'warm_rank':'wet_rank'][i],years=climate.sample_years[i];
        rows.push([temperature?'Warm rank / years':'Wet rank / years',Number.isFinite(rank)&&Number.isFinite(years)?`${fmt(rank,Number.isInteger(rank)?0:1)} / ${fmt(years,0)}`:'Unavailable']);
        const rec=climate.record[i],high=temperature?'warm':'wet',low=temperature?'cold':'dry';
        note=rec===1?`Record ${high}`:rec===2?`Tied record ${high}`:rec===3?`Record ${low}`:rec===4?`Tied record ${low}`:'';
      }
      reference='Departure: 1991–2020. Percentile and rank: matching periods in the available record beginning in 1895; rank 1 is warmest/wettest.';
      if(selection.metric==='spi'){
        rows.push([`SPI-${selection.duration}`,fmt(data.spi[i])],['SPI calibration years',fmt(data.sample_years[i],0)]);
        reference+=' SPI calibration: 1895–2020.';
        if(!Number.isFinite(data.spi[i]))note=Number.isFinite(data.spi_status[i])?(statuses[data.spi_status[i]]||'Estimate withheld'):'Outside available data footprint';
      }
    }
    return {rows,note,reference};
  }
  const api={cellAt,decode,category,styles,styleFor,resolveSelection,shiftDate,pointStats,companions};
  if (typeof module !== 'undefined') module.exports=api;
  if (!root.document) return;
  if(new URLSearchParams(location.search).get('embedded')==='1')document.body.classList.add('embedded');
  const $=id=>document.getElementById(id), metrics={events:[]}, cache=new Map();
  let manifest, active, overlay, sequence=0, querySequence=0, selected=null, selectionBox;
  const modeState={current:{frequency:'current',variable:'precipitation',metric:'total',period:'7day'},monthly:{frequency:'monthly',variable:'precipitation',metric:'total',duration:1},daily:{frequency:'daily',variable:'precipitation',metric:'total'}};
  const map=L.map('map',{minZoom:4,maxZoom:12}).setView([34.3,-109],6);
  map.attributionControl.addAttribution('Climate: PRISM via RCC-ACIS');
  const bounds=[[30.7291666667,-115.6458333333],[37.6458333333,-102.3958333333]];
  function reset(){map.fitBounds(bounds);}
  reset(); L.control.scale({imperial:true,metric:true}).addTo(map);
  function recordMetric(name,start,extra={}){
    metrics.events.push({name,ms:Math.round((performance.now()-start)*100)/100,...extra});
    if(metrics.events.length>200) metrics.events.shift();
    metrics.browserMemoryBytes=performance.memory?.usedJSHeapSize??null;
    $('metrics').textContent=JSON.stringify(metrics,null,2);
  }
  const NativeGrid=L.GridLayer.extend({
    createTile(coords){
      const tile=L.DomUtil.create('canvas'), size=this.getTileSize(); tile.width=size.x; tile.height=size.y;
      const ctx=tile.getContext('2d'), {style,layer,data}=this.options.payload, g=layer.grid;
      const origin=L.point(coords.x*size.x,coords.y*size.y), far=origin.add(size);
      const nw=map.unproject(origin,coords.z),se=map.unproject(far,coords.z);
      const r0=Math.max(0,Math.floor((g.north-nw.lat)/g.dy)),r1=Math.min(g.rows-1,Math.floor((g.north-se.lat)/g.dy));
      const c0=Math.max(0,Math.floor((nw.lng-g.west)/g.dx)),c1=Math.min(g.cols-1,Math.floor((se.lng-g.west)/g.dx));
      // Project each native cell's edges. Display and queries share the same geographic grid.
      for(let r=r0;r<=r1;r++){
        const y0=map.project([g.north-r*g.dy,0],coords.z).y-origin.y;
        const y1=map.project([g.north-(r+1)*g.dy,0],coords.z).y-origin.y;
        for(let c=c0;c<=c1;c++){
          const k=category(style,data,r*g.cols+c); if(k<0)continue;
          const x0=map.project([0,g.west+c*g.dx],coords.z).x-origin.x;
          const x1=map.project([0,g.west+(c+1)*g.dx],coords.z).x-origin.x;
          ctx.fillStyle=style.colors[k];ctx.fillRect(Math.floor(x0),Math.floor(y0),Math.ceil(x1)-Math.floor(x0),Math.ceil(y1)-Math.floor(y0));
        }
      }
      return tile;
    }
  });
  function loadData(id){
    if(!cache.has(id)){
      while(cache.size>=3)cache.delete(cache.keys().next().value);
      const layer=manifest.layers[id];
      const pending=fetch(layer.file).then(r=>{if(!r.ok)throw Error('Local climate file unavailable. Rebuild the pilot.');return r.arrayBuffer();}).then(b=>decode(b,layer)).catch(e=>{if(cache.get(id)===pending)cache.delete(id);throw e;});
      cache.set(id,pending);
    }
    const promise=cache.get(id);cache.delete(id);cache.set(id,promise);return promise;
  }
  async function query(latlng){
    if(!active)return;
    const queryToken=++querySequence,view=active;
    const tick=performance.now(),{id,layer,data,style,selection}=active,g=layer.grid,i=cellAt(g,latlng.lat,latlng.lng);
    selected=latlng;
    if(selectionBox)map.removeLayer(selectionBox);
    const coord=`${latlng.lat.toFixed(3)}°, ${latlng.lng.toFixed(3)}°`;
    const period=selection.frequency==='daily'?displayDate(selection.date):selection.frequency==='current'?selection.period==='current'?`As of ${displayDate(layer.date)}`:`${displayDate(layer.start_date)} to ${displayDate(layer.date)}`:layer.period;
    if(i<0){$('readout').innerHTML=`<h3>${coord}</h3><p>Outside this product’s source grid.</p>`;return;}
    const r=Math.floor(i/g.cols),c=i%g.cols;
    selectionBox=L.rectangle([[g.north-(r+1)*g.dy,g.west+c*g.dx],[g.north-r*g.dy,g.west+(c+1)*g.dx]],{color:'#172e3d',weight:2,fill:false,interactive:false}).addTo(map);
    function render(context={},message=''){
      const stats=pointStats(selection,data,i,context);
      if(category(style,data,i)<0)stats.note='No supported climate value at this source cell.';
      $('readout').innerHTML=`<h3>${coord}</h3><p>${period}</p>${stats.note?`<p><strong>${stats.note}</strong></p>`:''}<table><tbody>${stats.rows.map(([k,v])=>`<tr><th scope="row">${k}</th><td>${v}</td></tr>`).join('')}</tbody></table>${message?`<p>${message}</p>`:''}<p class="point-reference">${stats.reference}</p><p>Source cell center: ${(g.north-(r+.5)*g.dy).toFixed(4)}°, ${(g.west+(c+.5)*g.dx).toFixed(4)}°</p>`;
    }
    const related=companions(manifest,selection,layer);
    render({},related.length?'Loading matching comparison statistics…':'');
    if(related.length){
      const results=await Promise.allSettled(related.map(async p=>{
        const d=await loadData(p.id),l=manifest.layers[p.id],j=cellAt(l.grid,latlng.lat,latlng.lng);
        // Monthly companions must share the exact cell geometry as well as the window.
        if(selection.frequency==='monthly'&&Object.keys(g).some(k=>g[k]!==l.grid[k]))throw Error('Comparison grid mismatch');
        return p.metric?{[p.metric]:j<0?NaN:d.value[j]}:d;
      }));
      if(queryToken!==querySequence||active!==view)return;
      const context=Object.assign({},...results.filter(x=>x.status==='fulfilled').map(x=>x.value));
      render(context,results.some(x=>x.status==='rejected')?'Some matching comparison statistics are unavailable.':'');
    }
    recordMetric('query',tick,{layer:id,cell:i});
  }
  async function change(){
    if(!manifest)return;
    const token=++sequence;
    active=null;if(overlay){map.removeLayer(overlay);overlay=null;}if(selectionBox){map.removeLayer(selectionBox);selectionBox=null;}
    $('status').textContent='Loading selected climate map…';$('readout').innerHTML='<h3>Location details</h3><p>Loading selected map…</p>';
    try{
      const selection=resolveSelection(manifest,controlSelection());
      modeState[selection.frequency]={...selection};
      const {id}=selection,style=styleFor(selection);
      const layer=manifest.layers[id],tick=performance.now(),cached=cache.has(id);
      const descriptor=selection.frequency==='current'?manifest.current.products[selection.product]:null;
      const period=selection.frequency==='daily'?displayDate(selection.date):descriptor&&layer?selection.period==='current'?`As of ${displayDate(layer.date)}`:`${displayDate(layer.start_date)} to ${displayDate(layer.date)}`:layer?.period||(descriptor?descriptor.period_label:'Period unavailable');
      $('layer-title').textContent=descriptor?descriptor.title:style.kind==='spi'?`SPI-${selection.duration}`:style.title;$('layer-period').textContent=descriptor&&layer?`${descriptor.period_label} · ${period}`:period;
      $('legend').innerHTML=style.labels.map((label,i)=>`<div><span class="swatch" style="background:${style.colors[i]}"></span>${label}</div>`).join('');
      $('reference').textContent=(layer?.reference||descriptor?.description||'Daily PRISM cache; no date substitution or zero filling.')+(selection.frequency==='daily'?` Local cache: ${displayDate(manifest.daily.first_date)} to ${displayDate(manifest.daily.latest_date)}.`:'');
      $('product-link').hidden=!descriptor;
      if(descriptor)$('product-link').href=location.pathname.includes('/interactive-maps/')?descriptor.product_page:descriptor.public_url;
      if(!selection.available){
        $('resolution').textContent='';
        $('status').textContent=descriptor?`${descriptor.title} is unavailable in the local cache. ${descriptor.note} No other date has been substituted.`:`No verified ${style.title.toLowerCase()} map for ${period}. No other date has been substituted.`;
        $('readout').innerHTML=descriptor?'<h3>Location details</h3><p>This snapshot is unavailable. Choose another metric or period, or follow the static product link.</p>':'<h3>Location details</h3><p>Selected date or reference data unavailable. Choose another date or metric.</p>';
        return;
      }
      const data=await loadData(id);if(token!==sequence)return;
      active={id,layer,data,style,selection};
      overlay=new NativeGrid({payload:active,zIndex:200,opacity:Number($('opacity').value)/100,noWrap:true,bounds,updateWhenIdle:true,keepBuffer:1}).addTo(map);
      $('resolution').textContent=`Native grid: ${(layer.grid.dx*60).toFixed(1)} arc-minutes (about 4 km). Zooming does not add climate detail.`;
      $('status').textContent='';
      $('readout').innerHTML='<h3>Location details</h3><p>Select a location on the map.</p>';
      if(selected)query(selected);
      requestAnimationFrame(()=>requestAnimationFrame(()=>recordMetric('layer-ready',tick,{layer:id,cached,bytes:cached?0:layer.bytes})));
    }catch(e){if(token===sequence){$('status').textContent=e.message;$('readout').textContent='Selected map unavailable. Try another layer or rebuild the pilot.';}}
  }
  map.on('click',e=>query(e.latlng));
  $('map').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();query(map.getCenter());}});
  function controlSelection(){return {frequency:$('frequency').value,variable:$('variable').value,measure:$('measure').value,metric:$('metric').value,duration:$('period').value,period:$('period').value,date:$('date').value};}
  function syncSelectors(requested=controlSelection()){
    const s=resolveSelection(manifest,requested),daily=s.frequency==='daily',current=s.frequency==='current',catalog=current?manifest.current.variables:daily?manifest.daily.variables:manifest.variables;
    $('frequency').value=s.frequency;
    $('variable').replaceChildren(...Object.entries(catalog).map(([value,v])=>new Option(v.label,value)));
    $('variable').value=s.variable;
    $('measure-control').hidden=!current;
    if(current){$('measure').replaceChildren(...Object.entries(catalog[s.variable].measures).map(([value,m])=>new Option(m.label,value)));$('measure').value=s.measure;}
    const definition=current?catalog[s.variable].measures[s.measure]:catalog[s.variable];
    $('metric').replaceChildren(...Object.entries(definition.metrics).map(([value,label])=>new Option(label,value)));
    $('metric').value=s.metric;
    $('monthly-period-control').hidden=daily;$('daily-date-control').hidden=!daily;
    if(daily)$('date').value=s.date;
    else if(current){$('period').replaceChildren(...Object.entries(definition.periods[s.metric]).map(([value,label])=>new Option(label,value)));$('period').value=s.period;}
    else{$('period').replaceChildren(...manifest.durations.map(n=>new Option(`${n} month${n===1?'':'s'}`,String(n))));$('period').value=String(s.duration);}
    updateDateButtons();
  }
  function updateDateButtons(){const date=$('date').value;$('previous-date').disabled=!date||date<=manifest.daily.first_date;$('next-date').disabled=!date||date>=manifest.daily.latest_date;}
  $('frequency').addEventListener('change',()=>{const frequency=$('frequency').value;syncSelectors({...modeState[frequency],variable:$('variable').value});change();});
  $('variable').addEventListener('change',()=>{syncSelectors();change();});
  $('measure').addEventListener('change',()=>{syncSelectors();change();});
  $('metric').addEventListener('change',()=>{syncSelectors();change();});
  $('period').addEventListener('change',change);
  $('date').addEventListener('change',()=>{updateDateButtons();change();});
  for(const [id,step] of [['previous-date',-1],['next-date',1]])$(id).addEventListener('click',()=>{try{$('date').value=shiftDate($('date').value,step);updateDateButtons();change();}catch(e){$('status').textContent=e.message;}});
  $('reset').addEventListener('click',reset);
  $('opacity').addEventListener('input',()=>{const t=performance.now();$('opacity-value').textContent=$('opacity').value+'%';if(overlay)overlay.setOpacity(Number($('opacity').value)/100);requestAnimationFrame(()=>recordMetric('opacity',t));});
  $('download-metrics').addEventListener('click',()=>{
    metrics.resources=performance.getEntriesByType('resource').map(x=>({name:x.name,bytes:x.transferSize,ms:x.duration}));
    const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(metrics,null,2)],{type:'application/json'}));a.download='interactive-map-measurements.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
  });
  (async()=>{
    try{
      manifest=await fetch('manifest.json').then(r=>{if(!r.ok)throw Error('Manifest unavailable. Build the local pilot first.');return r.json();});
      if(manifest.schema!==5)throw Error('Rebuild the viewer to prepare Current Conditions measures.');
      $('variable').replaceChildren(...Object.entries(manifest.variables).map(([value,v])=>new Option(v.label,value)));
      $('period').replaceChildren(...manifest.durations.map(n=>new Option(`${n} month${n===1?'':'s'}`,String(n))));
      $('date').min=manifest.daily.first_date;$('date').max=manifest.daily.latest_date;$('date').value=manifest.daily.latest_date;
      modeState.daily.date=manifest.daily.latest_date;
      syncSelectors(modeState.current);
      for(const id of ['frequency','variable','measure','metric','period','date'])$(id).disabled=false;
      let base=null;
      let referenceLayers=[], referenceGeneration=0;
      map.createPane('geographicReference');
      map.getPane('geographicReference').style.zIndex='450';
      map.getPane('geographicReference').style.pointerEvents='none';
      function changeReferences(){
        const generation=++referenceGeneration;
        referenceLayers.forEach(layer=>map.removeLayer(layer));referenceLayers=[];
        const id=$('basemap').value,available=id==='terrain'||id==='satellite';
        $('reference-labels').disabled=!available;
        if(!available){$('reference-status').textContent='';return;}
        if(!$('reference-labels').checked){$('reference-status').textContent='';return;}
        $('reference-status').textContent='Loading roads and place names…';
        let loaded=0,failed=false;
        const definitions=Object.values(manifest.reference_overlays);
        for(const definition of definitions){
          const layer=L.tileLayer(definition.url,{attribution:definition.attribution,maxZoom:12,pane:'geographicReference'});
          layer.on('tileerror',()=>{if(generation===referenceGeneration){failed=true;$('reference-status').textContent='Some roads or labels are unavailable. Climate values remain available.';}});
          layer.once('load',()=>{if(generation===referenceGeneration){loaded++;if(loaded===definitions.length&&!failed)$('reference-status').textContent='';}});
          referenceLayers.push(layer);layer.addTo(map);
        }
      }
      $('reference-labels').addEventListener('change',changeReferences);
      function changeBasemap(){
        if(base){map.removeLayer(base);base=null;}
        const id=$('basemap').value,def=manifest.basemaps[id];
        changeReferences();
        if(!def){$('basemap-status').textContent='';return;}
        const current=L.tileLayer(def.url,{attribution:def.attribution,maxZoom:12,zIndex:100});
        let failed=false;base=current;
        $('basemap-status').textContent=`Loading ${def.title.toLowerCase()} basemap…`;
        current.on('tileerror',()=>{if(base===current){failed=true;$('basemap-status').textContent=`Some ${def.title.toLowerCase()} tiles are unavailable. Climate values and state outlines still work; try another basemap.`;}});
        current.on('load',()=>{if(base===current&&!failed)$('basemap-status').textContent='';});
        current.addTo(map);
      }
      $('basemap').disabled=false;
      $('basemap').addEventListener('change',changeBasemap);
      const requested=new URLSearchParams(location.search).get('basemap');
      if(requested==='off'||requested==='none')$('basemap').value='none';
      else if(manifest.basemaps[requested])$('basemap').value=requested;
      changeBasemap();
      fetch('boundaries.json').then(r=>r.json()).then(x=>L.geoJSON(x,{style:{color:'#344b56',weight:1,fill:false},interactive:false}).addTo(map)).catch(()=>{});
      await change();
      requestAnimationFrame(()=>requestAnimationFrame(()=>recordMetric('first-ready',0)));
      root.interactivePilot={map,query,metrics,get active(){return active;},change};
    }catch(e){$('status').textContent=e.message;}
  })();
})(typeof window!=='undefined'?window:globalThis);
