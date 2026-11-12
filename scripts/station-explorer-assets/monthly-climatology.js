window.SWCStationMonthlyClimatology = (() => {
  const finite=v=>typeof v==='number'&&Number.isFinite(v);
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const names=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const value=(v,unit)=>finite(v)?`${v.toFixed(unit==='in.'?2:1)} ${unit}`:'Unavailable';
  const range=(r,key,unit)=>finite(r[key+'_p25'])&&finite(r[key+'_p75'])?
    `${value(r[key+'_p25'],unit)}–${value(r[key+'_p75'],unit)}`:'Unavailable';
  const years=(r,key,which,short=false)=>{
    const list=String(r[key+'_'+which+'_years']||'').split(',').filter(Boolean);
    return short&&list.length>5?`${list.slice(0,5).join(', ')} +${list.length-5} tied years`:list.join(', ');
  };
  const extreme=(r,key,which,unit,short=false)=>finite(r[key+'_'+which])?
    `${value(r[key+'_'+which],unit)} (${years(r,key,which,short)})`:'Unavailable';
  const extremes=(r,key,unit,short=false)=>`Lowest: ${extreme(r,key,'min',unit,short)}; highest: ${extreme(r,key,'max',unit,short)}`;
  function months(reference,order='calendar') {
    const rows=reference?.monthly||[];
    return (order==='water'?[10,11,12,1,2,3,4,5,6,7,8,9]:[1,2,3,4,5,6,7,8,9,10,11,12])
      .map(month=>rows.find(row=>row.month===month)||{month,precipitation_years:0,temperature_years:0});
  }
  function chart(rows,temperature,baseline='1991–2020') {
    const left=42,right=546,top=16,bottom=172,step=(right-left)/12;
    const values=rows.flatMap(r=>temperature?[r.high_f,r.low_f,r.high_min,r.high_max,r.low_min,r.low_max,r.high_p25,r.high_p75,r.low_p25,r.low_p75]:[r.precip_median,r.precip_min,r.precip_max,r.precip_p25,r.precip_p75]).filter(finite);
    const min=temperature&&values.length?Math.floor(Math.min(...values)/10)*10:0;
    const max=temperature?Math.max(min+10,Math.ceil(Math.max(min,...values)/10)*10):Math.max(1,Math.ceil(Math.max(0,...values)));
    const x=i=>left+(i+.5)*step,y=v=>bottom-(v-min)/(max-min)*(bottom-top);
    let svg=[min,(min+max)/2,max].map(v=>`<line x1="${left}" x2="${right}" y1="${y(v)}" y2="${y(v)}" stroke="#dce5e8"/><text x="${left-6}" y="${y(v)+4}" text-anchor="end">${v.toFixed(temperature?0:1)}</text>`).join('');
    if(temperature)for(const [lower,upper,cls,opacity] of [
      ['min','max','monthly-extreme-envelope',.08],['p25','p75','monthly-variability-band',.22]])
      for(const [key,color] of [['high','#b35b37'],['low','#326a9e']]) {
      let segment=[];
      const flush=()=>{
        if(!segment.length)return;
        const points=segment.map(([r,i])=>`${x(i)},${y(r[key+'_'+upper])}`)
          .concat([...segment].reverse().map(([r,i])=>`${x(i)},${y(r[key+'_'+lower])}`)).join(' ');
        if(segment.length===1){const [r,i]=segment[0];
          svg+=`<rect class="${cls}" x="${x(i)-4}" y="${y(r[key+'_'+upper])}" width="8" height="${y(r[key+'_'+lower])-y(r[key+'_'+upper])}" fill="${color}" fill-opacity="${opacity}" stroke="${color}" stroke-opacity=".3" stroke-width=".6"/>`;
        }else svg+=`<polygon class="${cls}" points="${points}" fill="${color}" fill-opacity="${opacity}" stroke="${color}" stroke-opacity=".3" stroke-width=".6"/>`;
        segment=[];
      };
      rows.forEach((r,i)=>{if(finite(r[key+'_'+lower])&&finite(r[key+'_'+upper]))segment.push([r,i]);else flush();});flush();
    }
    if(temperature)for(const [field,color] of [['high_f','#b35b37'],['low_f','#326a9e']]) {
      let active=false;
      const path=rows.map((r,i)=>{if(!finite(r[field])){active=false;return '';}
        const command=active?'L':'M';active=true;return `${command}${x(i)},${y(r[field])}`;}).join(' ');
      svg+=`<path d="${path}" fill="none" stroke="${color}" stroke-width="2"/>`;
    }
    rows.forEach((r,i)=>{
      const available=temperature?finite(r.high_f)&&finite(r.low_f):finite(r.precip_inches);
      if(!temperature&&finite(r.precip_min)&&finite(r.precip_max))
        svg+=`<path class="monthly-range-whisker" d="M${x(i)},${y(r.precip_min)} V${y(r.precip_max)} M${x(i)-5},${y(r.precip_min)} h10 M${x(i)-5},${y(r.precip_max)} h10" fill="none" stroke="#496779" stroke-width="1.1"/>`;
      if(!temperature&&finite(r.precip_p25)&&finite(r.precip_p75))
        svg+=`<rect class="monthly-precipitation-box" x="${x(i)-11}" y="${y(r.precip_p75)}" width="22" height="${y(r.precip_p25)-y(r.precip_p75)}" fill="#b6d7e4" stroke="#24647f" stroke-width="1.2"/>`;
      if(!temperature&&finite(r.precip_median))
        svg+=`<path class="monthly-precipitation-median" d="M${x(i)-12},${y(r.precip_median)} h24" fill="none" stroke="#173d53" stroke-width="2.6"/>`;
      if(!available)svg+=`<text x="${x(i)}" y="${bottom-4}" text-anchor="middle" fill="#7c8c94">—</text>`;
      const text=temperature?`${names[r.month-1]} · Average high ${value(r.high_f,'°F')} · low ${value(r.low_f,'°F')}`:
        `${names[r.month-1]} · Median precipitation ${value(r.precip_median,'in.')}`;
      svg+=`<rect class="monthly-chart-day" data-month="${r.month}" x="${left+i*step}" y="${top}" width="${step}" height="${bottom-top}" fill="transparent" tabindex="${i===0?0:-1}" role="button" aria-label="${esc(text)}"><title>${esc(text)}</title></rect>`;
      svg+=`<text x="${x(i)}" y="193" text-anchor="middle">${names[r.month-1]}</text>`;
    });
    return `<svg viewBox="0 0 560 210" role="img" aria-label="${esc(baseline)} monthly ${temperature?'mean daily high and low temperatures in Fahrenheit with interannual ranges':'precipitation distribution in inches: median, middle 50%, and minimum–maximum'}">${svg}</svg>`;
  }
  function extremeCell(r,key,which,unit) {
    if(!finite(r[key+'_'+which]))return '—';
    const list=String(r[key+'_'+which+'_years']||'').split(',').filter(Boolean);
    const yearText=esc(list.join(', '));
    return `<strong>${value(r[key+'_'+which],unit)}</strong>`+
      (list.length>4?`<details class="monthly-tied-years"><summary>${list.length} years tied</summary><small>${yearText}</small></details>`:`<small>${yearText}</small>`);
  }
  function readout(r,temperature,baseline='1991–2020') {
    const support=(key,count)=>`${count??0}`+(finite(r[key+'_first_year'])&&finite(r[key+'_last_year'])?
      `<small>${r[key+'_first_year']}–${r[key+'_last_year']}</small>`:'');
    const row=(label,precip,high,low)=>`<tr><th scope="row">${label}</th>`+
      (temperature?`<td>${high}</td><td>${low}</td>`:`<td>${precip}</td>`)+`</tr>`;
    return `<div class="temperature-readout-heading"><strong>${names[r.month-1]} · ${esc(baseline)}</strong></div>`+
      `<table class="monthly-day-table" aria-label="${names[r.month-1]} monthly ${temperature?'temperature':'precipitation'} statistics"><thead><tr><th scope="col">Statistic</th>`+
      (temperature?'<th scope="col">High</th><th scope="col">Low</th>':'<th scope="col">Precipitation</th>')+'</tr></thead><tbody>'+
      row('Average',value(r.precip_inches,'in.'),value(r.high_f,'°F'),value(r.low_f,'°F'))+
      row('Median',value(r.precip_median,'in.'),value(r.high_median,'°F'),value(r.low_median,'°F'))+
      row('Middle 50%',range(r,'precip','in.'),range(r,'high','°F'),range(r,'low','°F'))+
      row('Lowest',extremeCell(r,'precip','min','in.'),extremeCell(r,'high','min','°F'),extremeCell(r,'low','min','°F'))+
      row('Highest',extremeCell(r,'precip','max','in.'),extremeCell(r,'high','max','°F'),extremeCell(r,'low','max','°F'))+
      row('Eligible years',support('precip',r.precipitation_years),support('high',r.temperature_years),support('low',r.temperature_years))+
      '</tbody></table>';
  }
  function panel(reference,order='calendar',period='reference') {
    const active=period==='record'&&reference.full_record?reference.full_record:reference;
    const baseline=active.baseline||'1991–2020';
    const rows=months(active,order);
    return `<p class="detail-chart-note">Project-calculated ${esc(baseline)} monthly climate · At least ${active.minimum_years||20} eligible years per month · Not official NOAA normals.</p>`+
      (period==='record'?'<p class="detail-chart-note">Uses available cached station/ThreadEx history and finished calendar months only. Eligible year spans differ by month and variable; see the tables.</p>':'')+
      `<label>Reference period <select data-climatology-period><option value="reference"${period==='reference'?' selected':''}>1991–2020</option><option value="record"${period==='record'?' selected':''}${reference.full_record?'':' disabled'}>Full available record</option></select></label>`+
      `<label>Month order <select data-month-order><option value="calendar"${order==='calendar'?' selected':''}>Calendar year · Jan–Dec</option><option value="water"${order==='water'?' selected':''}>Water year · Oct–Sep</option></select></label>`+
      `<p class="detail-chart-note">Ranges show variation between monthly values across eligible years in the selected reference period—not daily swings or confidence intervals.</p>`+
      `<p class="detail-chart-note">Hover, tap or focus a month to update both tables. Use left/right arrow keys to move between months.</p>`+
      `<div class="detail-charts"><figure><figcaption>Monthly precipitation distribution (inches)</figcaption><p class="detail-chart-note">Box: middle 50% · Bold mark: median · Whiskers: lowest–highest</p>${chart(rows,false,baseline)}<div class="chart-readout temperature-readout monthly-readout" data-month-readout="precipitation" aria-live="polite">${readout(rows[0],false,baseline)}</div></figure>`+
      `<figure><figcaption>Monthly mean daily high and low temperature (°F)</figcaption><p class="detail-chart-note">Orange: high · Blue: low · Lines: average · Inner bands: middle 50% · Light outer bands: lowest–highest</p>${chart(rows,true,baseline)}<div class="chart-readout temperature-readout monthly-readout" data-month-readout="temperature" aria-live="polite">${readout(rows[0],true,baseline)}</div></figure></div>`+
      `<details class="monthly-reference"><summary>Monthly values, extremes and reference coverage</summary><div class="monthly-table-scroll"><table class="monthly-climatology-table"><thead><tr><th>Month</th><th>Precip median (in.)</th><th>Mean high (°F)</th><th>Mean low (°F)</th><th>Precip years</th><th>Temp years</th></tr></thead><tbody>`+
      rows.map(r=>`<tr><th scope="row">${names[r.month-1]}</th><td>${finite(r.precip_median)?r.precip_median.toFixed(2):'—'}<small>Average: ${value(r.precip_inches,'in.')}</small><small>Middle 50%: ${range(r,'precip','in.')}</small><small>${esc(extremes(r,'precip','in.'))}</small></td><td>${finite(r.high_f)?r.high_f.toFixed(1):'—'}<small>Middle 50%: ${range(r,'high','°F')}</small><small>${esc(extremes(r,'high','°F'))}</small></td><td>${finite(r.low_f)?r.low_f.toFixed(1):'—'}<small>Middle 50%: ${range(r,'low','°F')}</small><small>${esc(extremes(r,'low','°F'))}</small></td><td>${r.precipitation_years}</td><td>${r.temperature_years}</td></tr>`).join('')+
      `</tbody></table></div><p>Lowest/highest and their year(s) describe eligible months in ${esc(baseline)}. Only finished calendar months are included. Temperature endpoints describe monthly mean daily highs/lows, not individual daily temperature records. Dry-month boxes can collapse to zero.</p><p>${esc(active.method)}</p><p>${esc(active.variability)}</p><p>Gaps mean insufficient reference coverage, not zero. Ordering changes the display only; this section is independent of the selected summary period.</p></details>`;
  }
  function section(reference) {
    if(!reference)return '';
    return `<details class="station-cumulative station-climatology"><summary>Typical climate at this station</summary><div class="monthly-climatology-content">${panel(reference)}</div></details>`;
  }
  function mount(container,reference) {
    if(!container||!reference)return;
    let selected=1,period='reference',order='calendar';
    function selectMonth(month) {
      const active=period==='record'&&reference.full_record?reference.full_record:reference;
      const r=months(active).find(row=>row.month===Number(month));
      if(!r)return;
      selected=r.month;
      for(const [kind,temperature] of [['precipitation',false],['temperature',true]]) {
        const target=container.querySelector(`[data-month-readout="${kind}"]`);
        if(target)target.innerHTML=readout(r,temperature,active.baseline||'1991–2020');
      }
      container.querySelectorAll('.monthly-chart-day').forEach(hit=>{
        const matches=Number(hit.dataset.month)===selected;
        hit.tabIndex=matches?0:-1;hit.classList.toggle('monthly-selected',matches);
      });
    }
    const selectFromEvent=event=>{
      const hit=event.target.closest?.('.monthly-chart-day');
      if(hit&&container.contains(hit))selectMonth(hit.dataset.month);
    };
    for(const name of ['pointerover','focusin','click'])container.addEventListener(name,selectFromEvent);
    container.addEventListener('keydown',event=>{
      const hit=event.target.closest?.('.monthly-chart-day');
      if(!hit||!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
      const hits=[...hit.closest('figure').querySelectorAll('.monthly-chart-day')];
      const i=hits.indexOf(hit),next=event.key==='Home'?0:event.key==='End'?hits.length-1:
        Math.max(0,Math.min(hits.length-1,i+(event.key==='ArrowRight'?1:-1)));
      event.preventDefault();hits[next].focus();
    });
    container.addEventListener('change',event=>{
      if(event.target.matches('[data-month-order]'))order=event.target.value==='water'?'water':'calendar';
      else if(event.target.matches('[data-climatology-period]'))period=event.target.value==='record'&&reference.full_record?'record':'reference';
      else return;
      container.querySelector('.monthly-climatology-content').innerHTML=panel(reference,order,period);
      selectMonth(selected);
    });
    selectMonth(selected);
  }
  return {months,chart,panel,section,mount,readout};
})();
