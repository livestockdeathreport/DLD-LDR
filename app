(function () {
  'use strict';

  /* ================================================================
   *  Config
   * ================================================================ */
  var REFRESH_MS = 30000; // รีเฟรชแดชบอร์ดอัตโนมัติทุก 30 วินาที
  var GEO_URLS = [
    'https://cdn.jsdelivr.net/gh/kongvut/thai-province-data@master/api/latest/province_with_district_and_sub_district.json',
    'https://raw.githubusercontent.com/kongvut/thai-province-data/master/api/latest/province_with_district_and_sub_district.json'
  ];
  var PINE = '#1E4D40';
  var ALERT = '#B3382C';
  var PALETTE = ['#1E4D40', '#C58B2A', '#4A6C8C', '#8A5A7A', '#7FA37B'];
  var OTHER_COLOR = '#A9A296';
  var OTHER_LABEL = 'อื่นๆ';
  var OTHER_VALUE = '__other__';
  // ต้องตรงกับ ALLOWED_SPECIES / ALLOWED_CAUSES ใน Code.gs
  var SPECIES_OPTIONS = ['โค', 'กระบือ', 'ไก่เนื้อ', 'ไก่ไข่', 'สุกร', 'เป็ดเนื้อ', 'เป็ดไข่', 'เป็ดเทศ', 'แพะ', 'แกะ', 'นกกระทา', 'ไก่พื้นเมือง', 'ไก่งวง', 'ห่าน', 'นกกระจอกเทศ'];
  var CAUSE_OPTIONS = ['อุทกภัย', 'วาตภัย', 'อัคคีภัย', 'ภัยสงคราม', 'โรคระบาด'];
  // เส้นแบ่งจังหวัด (GeoJSON 77 จังหวัด คุณสมบัติ pro_th = ชื่อจังหวัดภาษาไทย) สำหรับ Heatmap
  var PROVINCE_GEO_URLS = [
    'https://cdn.jsdelivr.net/gh/chingchai/OpenGISData-Thailand@master/provinces.geojson',
    'https://raw.githubusercontent.com/chingchai/OpenGISData-Thailand/master/provinces.geojson'
  ];
  var HEAT_STOPS = [[0, [79, 155, 217]], [0.5, [244, 211, 94]], [1, [192, 57, 43]]]; // ฟ้า -> เหลือง -> แดง
  var HEAT_ZERO = '#E4EEF7'; // จังหวัดที่ยังไม่มีรายงาน

  /* ================================================================
   *  Utilities
   * ================================================================ */
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var pad = function (n) { return String(n).padStart(2, '0'); };
  var nf = new Intl.NumberFormat('th-TH');
  var collator = new Intl.Collator('th');

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function norm(s) { return String(s || '').replace(/\s+/g, ' ').trim(); }
  function ymd(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function thaiDate(s) { var p = s.split('-'); return p[2] + '/' + p[1] + '/' + (Number(p[0]) + 543); }
  function todayStr() { return ymd(new Date()); }
  function optionsHtml(list, placeholder) {
    return '<option value="">' + placeholder + '</option>' +
      list.map(function (v) { return '<option value="' + esc(v) + '">' + esc(v) + '</option>'; }).join('') +
      '<option value="' + OTHER_VALUE + '">อื่นๆ (ระบุ)</option>';
  }

  // สถานะการดำเนินการของเจ้าหน้าที่
  var STATUS = {
    'new':         { label: 'รอรับเรื่อง',        cls: 'st--new' },
    'in_progress': { label: 'กำลังดำเนินการ',      cls: 'st--prog' },
    'done':        { label: 'ดำเนินการเรียบร้อย',  cls: 'st--done' }
  };
  function statusOf(r) { return STATUS[r.status] || STATUS['new']; }
  function statusTime(r) {
    if (!r.statusAt || r.status === 'new') return '';
    return (r.status === 'done' ? 'เสร็จเมื่อ ' : 'รับงานเมื่อ ') + thaiDate(r.statusAt.slice(0, 10)) + ' ' + r.statusAt.slice(11, 16) + ' น.';
  }
  // เบอร์โทร: รับ 0xxxxxxxxx / +66xxxxxxxxx (ตัดช่องว่าง ขีด วงเล็บ) -> '' ถ้าไม่ถูกต้อง
  function normPhone(v) {
    var s = String(v || '').replace(/[\s\-().]/g, '');
    if (s.indexOf('+66') === 0) s = '0' + s.slice(3);
    else if (s.indexOf('66') === 0 && s.length >= 11) s = '0' + s.slice(2);
    return /^0\d{8,9}$/.test(s) ? s : '';
  }

  var toast = Swal.mixin({
    toast: true, position: 'top-end', showConfirmButton: false, timer: 4000, timerProgressBar: true
  });

  /* ================================================================
   *  API (เรียก /api บน Vercel)
   * ================================================================ */
  var hasGAS = true; // ระบบใหม่เรียก /api เสมอ (ไม่มีโหมดทดสอบ)

  var API_ROUTES = {
    getReports:  { method: 'GET',  url: '/api/reports' },
    getContacts: { method: 'GET',  url: '/api/contacts' },
    saveReport:  { method: 'POST', url: '/api/save-report' },
    me:           { method: 'GET',    url: '/api/auth' },
    login:        { method: 'POST',   url: '/api/auth' },
    logout:       { method: 'DELETE', url: '/api/auth' },
    staffReports: { method: 'GET',    url: '/api/staff-reports' },
    updateStatus: { method: 'POST',   url: '/api/update-status' }
  };

  function api(fn, payload) {
    var r = API_ROUTES[fn];
    if (!r) return Promise.reject(new Error('ไม่รู้จักฟังก์ชัน ' + fn));
    var opt = { method: r.method, headers: { 'Content-Type': 'application/json' } };
    if (r.method === 'POST') opt.body = JSON.stringify(payload);
    return fetch(r.url, opt).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (!res.ok) {
          var err = new Error((data && data.error) || ('เซิร์ฟเวอร์ตอบกลับผิดพลาด (' + res.status + ')'));
          err.status = res.status;
          throw err;
        }
        return data;
      });
    });
  }

  var demoDB = [];
  function uniqCauses(animals) {
    var seen = {}, out = [];
    animals.forEach(function (a) { if (a.cause && !seen[a.cause]) { seen[a.cause] = 1; out.push(a.cause); } });
    return out.join(', ');
  }
  function seedDemo() {
    var spots = [
      ['เชียงใหม่', 'เมืองเชียงใหม่', 'ศรีภูมิ', 18.79, 98.99], ['ขอนแก่น', 'เมืองขอนแก่น', 'ในเมือง', 16.43, 102.83],
      ['นครราชสีมา', 'เมืองนครราชสีมา', 'ในเมือง', 14.97, 102.10], ['สุราษฎร์ธานี', 'เมืองสุราษฎร์ธานี', 'ตลาด', 9.14, 99.33],
      ['พิษณุโลก', 'เมืองพิษณุโลก', 'ในเมือง', 16.82, 100.26], ['อุบลราชธานี', 'เมืองอุบลราชธานี', 'ในเมือง', 15.24, 104.85]
    ];
    var species = SPECIES_OPTIONS.slice(0, 8);
    for (var i = 0; i < 40; i++) {
      var s = spots[Math.floor(Math.random() * spots.length)];
      var d = new Date(); d.setDate(d.getDate() - Math.floor(Math.random() * 30));
      var animals = [];
      for (var k = 0, m = 1 + Math.floor(Math.random() * 3); k < m; k++) {
        animals.push({
          name: species[Math.floor(Math.random() * species.length)],
          count: 1 + Math.floor(Math.random() * 120),
          cause: CAUSE_OPTIONS[Math.floor(Math.random() * CAUSE_OPTIONS.length)]
        });
      }
      demoDB.push({
        id: 'DEMO-' + (1000 + i), ts: ymd(d) + ' ' + pad(8 + Math.floor(Math.random() * 10)) + ':' + pad(Math.floor(Math.random() * 60)) + ':00',
        found: ymd(d), province: s[0], district: s[1], subdistrict: s[2],
        lat: s[3] + (Math.random() - .5) * .08, lng: s[4] + (Math.random() - .5) * .08,
        animals: animals, total: animals.reduce(function (a, b) { return a + b.count; }, 0), cause: uniqCauses(animals)
      });
    }
    demoDB.sort(function (a, b) { return a.ts.localeCompare(b.ts); });
  }
  var demoContacts = [
    { province: 'เชียงใหม่', agency: 'สำนักงานปศุสัตว์จังหวัดเชียงใหม่', name: 'นายสมชาย ใจดี', phone: '053-000-000' },
    { province: 'เชียงใหม่', agency: 'ศูนย์ป้องกันและบรรเทาสาธารณภัยที่ 1', name: 'นางสุดา รักไทย', phone: '053-111-111' },
    { province: 'ขอนแก่น', agency: 'สำนักงานปศุสัตว์จังหวัดขอนแก่น', name: 'นายวิชัย มั่นคง', phone: '043-000-000' }
  ];
  function demoApi(fn, args) {
    return new Promise(function (resolve, reject) {
      setTimeout(function () {
        if (fn === 'getReports') return resolve(JSON.parse(JSON.stringify(demoDB)));
        if (fn === 'getContacts') return resolve(demoContacts);
        if (fn === 'saveReport') {
          var p = args[0], now = new Date();
          var animals = p.animals.map(function (a) { return { name: a.name, count: Number(a.count), cause: a.cause }; });
          var id = 'DEMO-' + Math.floor(Math.random() * 90000 + 10000);
          demoDB.push({
            id: id, ts: ymd(now) + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds()),
            found: p.foundDate, province: p.province, district: p.district, subdistrict: p.subdistrict,
            lat: p.lat === '' ? null : p.lat, lng: p.lng === '' ? null : p.lng, animals: animals,
            total: animals.reduce(function (s, a) { return s + a.count; }, 0), cause: uniqCauses(animals)
          });
          return resolve({ ok: true, id: id });
        }
        reject(new Error('ไม่รู้จักฟังก์ชัน ' + fn));
      }, 400);
    });
  }

  /* ================================================================
   *  State
   * ================================================================ */
  var state = {
    geo: null, coord: null, gps: null,
    reports: [], filtered: [], loaded: false, sig: '',
    page: 1, pageSize: 10, areaLevel: 'province',
    view: 'form', timer: null, contactLoaded: false, staff: null,
    map: null, layer: null, markers: {}, charts: {},
    mapMode: 'points', heatLayer: null, heatLoading: null, heatLegend: null, provStats: {}, heatMax: 1
  };

  /* ================================================================
   *  Tabs (แจ้งเหตุ / แดชบอร์ด / ติดต่อเจ้าหน้าที่)
   * ================================================================ */
  function showView(name) {
    state.view = name;
    $$('.tab').forEach(function (t) {
      var on = t.dataset.view === name;
      t.classList.toggle('is-active', on);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    ['form', 'dashboard', 'contact'].forEach(function (v) {
      $('#view-' + v).classList.toggle('is-active', v === name);
    });
    window.scrollTo(0, 0);

    clearInterval(state.timer);
    if (name === 'dashboard') {
      initMap();
      loadReports(false);
      state.timer = setInterval(function () { if (!document.hidden) loadReports(true); }, REFRESH_MS);
    }
    if (name === 'contact' && !state.contactLoaded) loadContacts();
  }
  $$('.tab').forEach(function (t) { t.addEventListener('click', function () { showView(t.dataset.view); }); });

  // กล่องสีแดง "ติดต่อเจ้าหน้าที่ส่วนกลาง" ในหน้าแจ้งเหตุ
  var promo = $('#promoContact');
  promo.addEventListener('click', function () { showView('contact'); });
  promo.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); showView('contact'); }
  });

  /* ================================================================
   *  Dropdown ที่พิมพ์ค้นหาได้ — ครอบ <select> เดิม (ค่าจริงยังอยู่ใน select)
   * ================================================================ */
  var combos = [];

  function enhanceSelect(sel) {
    if (sel._combo) return sel._combo;

    var wrap = document.createElement('div');
    wrap.className = 'combo';
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'combo__input';
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-expanded', 'false');
    input.setAttribute('autocomplete', 'off');
    input.spellcheck = false;
    if (sel.id) {
      input.id = sel.id + '-search';
      var label = document.querySelector('label[for="' + sel.id + '"]');
      if (label) label.htmlFor = input.id;
    }
    if (sel.getAttribute('aria-label')) input.setAttribute('aria-label', sel.getAttribute('aria-label'));
    var list = document.createElement('ul');
    list.className = 'combo__list';
    list.setAttribute('role', 'listbox');
    list.hidden = true;

    sel.parentNode.insertBefore(wrap, sel);
    wrap.appendChild(sel);
    wrap.appendChild(input);
    wrap.appendChild(list);
    sel.classList.add('combo__src');
    sel.tabIndex = -1;

    var items = [], active = -1, isOpen = false;

    function optionsOf() {
      return Array.prototype.filter.call(sel.options, function (o) { return o.value !== ''; });
    }
    function selectedText() {
      var o = sel.options[sel.selectedIndex];
      return o && o.value !== '' ? o.text : '';
    }
    function sync() {
      if (!isOpen) input.value = selectedText();
      input.placeholder = sel.options.length && sel.options[0].value === '' ? sel.options[0].text : '';
      input.disabled = sel.disabled;
      wrap.classList.toggle('is-disabled', sel.disabled);
      if (sel.getAttribute('aria-invalid') === 'true') input.setAttribute('aria-invalid', 'true');
      else input.removeAttribute('aria-invalid');
    }
    function scrollActive() {
      var el = list.querySelector('.is-active');
      if (!el) return;
      if (el.offsetTop < list.scrollTop) list.scrollTop = el.offsetTop;
      else if (el.offsetTop + el.offsetHeight > list.scrollTop + list.clientHeight) list.scrollTop = el.offsetTop + el.offsetHeight - list.clientHeight;
    }
    function render(query) {
      var q = (query || '').trim().toLowerCase();
      items = optionsOf().filter(function (o) { return !q || o.text.toLowerCase().indexOf(q) !== -1; });
      active = -1;
      items.forEach(function (o, i) { if (active < 0 && o.value === sel.value) active = i; });
      if (active < 0 && items.length) active = 0;
      list.innerHTML = items.length
        ? items.slice(0, 300).map(function (o, i) {
          return '<li role="option" data-i="' + i + '" class="combo__opt' + (i === active ? ' is-active' : '') +
            (o.value === sel.value ? ' is-selected' : '') + '">' + esc(o.text) + '</li>';
        }).join('')
        : '<li class="combo__empty">ไม่พบรายการที่ค้นหา</li>';
      scrollActive();
    }
    function updateActive() {
      Array.prototype.forEach.call(list.children, function (li, i) { li.classList.toggle('is-active', i === active); });
      scrollActive();
    }
    function open() {
      if (sel.disabled || isOpen) return;
      isOpen = true;
      var r = wrap.getBoundingClientRect();
      var below = window.innerHeight - r.bottom;
      wrap.classList.toggle('combo--up', below < 260 && r.top > below);
      list.hidden = false;
      input.setAttribute('aria-expanded', 'true');
      render('');
    }
    function close() {
      isOpen = false;
      list.hidden = true;
      input.setAttribute('aria-expanded', 'false');
      sync();
    }
    function choose(i) {
      var o = items[i];
      if (!o) return;
      sel.value = o.value;
      close();
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    }

    input.addEventListener('focus', function () { open(); input.select(); });
    input.addEventListener('click', open);
    input.addEventListener('input', function () { if (!isOpen) open(); render(input.value); });
    input.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        if (!isOpen) { open(); return; }
        if (!items.length) return;
        active = (active + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
        updateActive();
      } else if (e.key === 'Enter') {
        if (isOpen) { e.preventDefault(); if (active >= 0) choose(active); }
      } else if (e.key === 'Escape') {
        if (isOpen) { e.preventDefault(); close(); }
      } else if (e.key === 'Tab') {
        close();
      }
    });
    input.addEventListener('blur', function () { setTimeout(close, 120); });
    list.addEventListener('mousedown', function (e) {
      e.preventDefault(); // กัน input เสีย focus ก่อนเลือกรายการ
      var li = e.target.closest('.combo__opt');
      if (li) choose(Number(li.dataset.i));
    });

    new MutationObserver(function () {
      sync();
      if (sel.disabled && isOpen) close();
      else if (isOpen) render(input.value);
    }).observe(sel, { childList: true, attributes: true, attributeFilter: ['disabled', 'aria-invalid'] });

    sel.focus = function () { input.focus(); };
    sel._combo = { refresh: sync, el: sel };
    combos.push(sel._combo);
    sync();
    return sel._combo;
  }

  function refreshCombos() {
    combos = combos.filter(function (c) { return document.body.contains(c.el); });
    combos.forEach(function (c) { c.refresh(); });
  }

  /* ================================================================
   *  หน้า 1: ที่อยู่ จังหวัด > อำเภอ > ตำบล
   * ================================================================ */
  var selProv = $('#province'), selDist = $('#district'), selSub = $('#subdistrict');
  [selProv, selDist, selSub].forEach(enhanceSelect);

  function resetSelect(sel, text, disabled) {
    sel.innerHTML = '<option value="">' + text + '</option>';
    sel.disabled = disabled !== false;
  }

  function compactGeo(raw) {
    function avg(list) {
      var v = list.filter(function (p) { return p && p.lat != null; });
      if (!v.length) return null;
      return {
        lat: v.reduce(function (s, p) { return s + p.lat; }, 0) / v.length,
        lng: v.reduce(function (s, p) { return s + p.lng; }, 0) / v.length
      };
    }
    var provinces = raw.map(function (p) {
      var districts = (p.districts || []).map(function (d) {
        var subs = (d.sub_districts || []).map(function (t) {
          return {
            name: t.name.th,
            lat: t.lat != null ? Number(t.lat) : null,
            lng: t.long != null ? Number(t.long) : null
          };
        });
        var c = avg(subs);
        // ตำบลที่ไม่มีพิกัดในชุดข้อมูล ใช้จุดกึ่งกลางของอำเภอแทน
        if (c) subs.forEach(function (s) { if (s.lat == null) { s.lat = c.lat; s.lng = c.lng; } });
        subs.sort(function (a, b) { return collator.compare(a.name, b.name); });
        return { name: d.name.th, subs: subs, center: c };
      });
      var pc = avg(districts.map(function (d) { return d.center; }));
      if (pc) districts.forEach(function (d) {
        if (!d.center) d.subs.forEach(function (s) { s.lat = pc.lat; s.lng = pc.lng; });
      });
      districts.sort(function (a, b) { return collator.compare(a.name, b.name); });
      return { name: p.name.th, districts: districts };
    });
    provinces.sort(function (a, b) { return collator.compare(a.name, b.name); });
    return provinces;
  }

  function setGeoStatus(kind) {
    var el = $('#geoStatus');
    if (kind === 'error') {
      el.innerHTML = 'โหลดข้อมูลจังหวัดไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้ว <button type="button" id="geoRetry">ลองใหม่</button>';
      $('#geoRetry').addEventListener('click', loadGeo);
    } else {
      el.textContent = '';
    }
  }

  function loadGeo() {
    resetSelect(selProv, 'กำลังโหลดข้อมูล…', true);
    setGeoStatus('loading');
    var i = 0;
    function attempt() {
      if (i >= GEO_URLS.length) {
        resetSelect(selProv, 'โหลดข้อมูลไม่สำเร็จ', true);
        setGeoStatus('error');
        return;
      }
      fetch(GEO_URLS[i++])
        .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(function (raw) {
          state.geo = compactGeo(raw);
          resetSelect(selProv, 'เลือกจังหวัด', false);
          state.geo.forEach(function (p, idx) { selProv.add(new Option(p.name, idx)); });
          resetSelect(selDist, 'เลือกอำเภอ/เขต', true);
          resetSelect(selSub, 'เลือกตำบล/แขวง', true);
        })
        .catch(attempt);
    }
    attempt();
  }

  selProv.addEventListener('change', function () {
    state.coord = null;
    resetSelect(selSub, 'เลือกตำบล/แขวง', true);
    if (selProv.value === '') return resetSelect(selDist, 'เลือกอำเภอ/เขต', true);
    resetSelect(selDist, 'เลือกอำเภอ/เขต', false);
    state.geo[selProv.value].districts.forEach(function (d, idx) { selDist.add(new Option(d.name, idx)); });
    clearErr('province');
  });
  selDist.addEventListener('change', function () {
    state.coord = null;
    if (selDist.value === '') return resetSelect(selSub, 'เลือกตำบล/แขวง', true);
    resetSelect(selSub, 'เลือกตำบล/แขวง', false);
    state.geo[selProv.value].districts[selDist.value].subs.forEach(function (s, idx) { selSub.add(new Option(s.name, idx)); });
    clearErr('district');
  });
  selSub.addEventListener('change', function () {
    if (selSub.value === '') { state.coord = null; return; }
    var s = state.geo[selProv.value].districts[selDist.value].subs[selSub.value];
    state.coord = s.lat != null ? { lat: s.lat, lng: s.lng } : null;
    clearErr('subdistrict');
  });

  /* ================================================================
   *  หน้า 1: รายการสัตว์ (Dynamic fields) — ชนิด / จำนวน / สาเหตุ
   * ================================================================ */
  var animalList = $('#animalList');

  function addAnimalRow(focus) {
    var row = document.createElement('div');
    row.className = 'animal';
    row.innerHTML =
      '<div class="field"><label class="m-only">ชนิดสัตว์</label>' +
        '<select class="a-name" aria-label="ชนิดสัตว์">' + optionsHtml(SPECIES_OPTIONS, 'เลือกชนิดสัตว์') + '</select>' +
        '<input type="text" class="a-name-other" maxlength="100" placeholder="พิมพ์ระบุชนิดสัตว์" aria-label="ระบุชนิดสัตว์อื่นๆ" hidden></div>' +
      '<div class="field"><label class="m-only">จำนวน (ตัว)</label>' +
        '<input type="number" class="a-count" min="1" step="1" inputmode="numeric" placeholder="0" aria-label="จำนวน (ตัว)"></div>' +
      '<div class="field"><label class="m-only">สาเหตุการตาย</label>' +
        '<select class="a-cause" aria-label="สาเหตุการตาย">' + optionsHtml(CAUSE_OPTIONS, 'เลือกสาเหตุ') + '</select>' +
        '<input type="text" class="a-cause-other" maxlength="100" placeholder="พิมพ์ระบุสาเหตุ" aria-label="ระบุสาเหตุอื่นๆ" hidden></div>' +
      '<button type="button" class="icon-btn a-remove" aria-label="ลบรายการนี้">' +
      '<svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true"><path d="M5.5 6h9M8 6V4.5h4V6M6.5 6l.6 9h5.8l.6-9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg></button>';
    animalList.appendChild(row);
    enhanceSelect($('.a-name', row));
    enhanceSelect($('.a-cause', row));
    updateAnimalUI();
    if (focus) $('.a-name', row).focus();
  }

  function updateAnimalUI() {
    var rows = $$('.animal', animalList);
    rows.forEach(function (r) { $('.a-remove', r).disabled = rows.length === 1; });
    var total = 0;
    rows.forEach(function (r) {
      var c = Number($('.a-count', r).value);
      if (isFinite(c) && c > 0) total += Math.floor(c);
    });
    $('#animalTotal').textContent = nf.format(total);
  }

  // เลือก "อื่นๆ (ระบุ)" -> แสดงช่องพิมพ์
  animalList.addEventListener('change', function (e) {
    var t = e.target;
    if (!t.matches('.a-name, .a-cause')) return;
    var field = t.closest('.field');
    var other = field.querySelector('.a-name-other, .a-cause-other');
    var isOther = t.value === OTHER_VALUE;
    other.hidden = !isOther;
    if (isOther) other.focus(); else other.value = '';
    t.removeAttribute('aria-invalid');
    other.removeAttribute('aria-invalid');
    $('#animalErr').textContent = '';
  });
  animalList.addEventListener('input', function (e) {
    if (e.target.matches('.a-count, .a-name-other, .a-cause-other')) {
      e.target.removeAttribute('aria-invalid');
      $('#animalErr').textContent = '';
      updateAnimalUI();
    }
  });
  animalList.addEventListener('click', function (e) {
    var btn = e.target.closest('.a-remove');
    if (!btn || btn.disabled) return;
    btn.closest('.animal').remove();
    updateAnimalUI();
  });
  $('#addAnimal').addEventListener('click', function () { addAnimalRow(true); });

  /* ================================================================
   *  หน้า 1: ตรวจสอบและบันทึก
   * ================================================================ */
  var form = $('#reportForm');
  var FORM_FIELDS = ['firstName', 'lastName', 'phone', 'foundDate', 'province', 'district', 'subdistrict'];

  function setErr(id, msg) {
    var el = $('#' + id);
    if (el) el.setAttribute('aria-invalid', 'true');
    var p = $('.err[data-for="' + id + '"]');
    if (p) p.textContent = msg;
  }
  function clearErr(id) {
    var el = $('#' + id);
    if (el) el.removeAttribute('aria-invalid');
    var p = $('.err[data-for="' + id + '"]');
    if (p) p.textContent = '';
  }
  ['firstName', 'lastName', 'phone', 'foundDate'].forEach(function (id) {
    $('#' + id).addEventListener('input', function () { clearErr(id); });
  });
  $('#foundDate').max = todayStr();

  function collect() {
    var first = null;
    function bad(el, id, msg) {
      if (id) setErr(id, msg); else el.setAttribute('aria-invalid', 'true');
      if (!first) first = el;
    }
    FORM_FIELDS.forEach(clearErr);
    $$('[aria-invalid]', animalList).forEach(function (el) { el.removeAttribute('aria-invalid'); });
    $('#animalErr').textContent = '';

    var v = function (id) { return $('#' + id).value.trim(); };
    var found = $('#foundDate').value;
    if (!found) bad($('#foundDate'), 'foundDate', 'กรุณาระบุวันที่พบสัตว์ตาย');
    else if (found > todayStr()) bad($('#foundDate'), 'foundDate', 'วันที่พบต้องไม่เกินวันนี้');
    if (!v('firstName')) bad($('#firstName'), 'firstName', 'กรุณากรอกชื่อ');
    if (!v('lastName')) bad($('#lastName'), 'lastName', 'กรุณากรอกนามสกุล');
    var phone = normPhone(v('phone'));
    if (!phone) bad($('#phone'), 'phone', 'กรุณากรอกเบอร์โทรให้ถูกต้อง เช่น 0812345678');
    if (selProv.value === '') bad(selProv, 'province', 'กรุณาเลือกจังหวัด');
    else if (selDist.value === '') bad(selDist, 'district', 'กรุณาเลือกอำเภอ/เขต');
    else if (selSub.value === '') bad(selSub, 'subdistrict', 'กรุณาเลือกตำบล/แขวง');

    var animals = [], animalBad = false;
    $$('.animal', animalList).forEach(function (r) {
      var sN = $('.a-name', r), oN = $('.a-name-other', r), c = $('.a-count', r);
      var sC = $('.a-cause', r), oC = $('.a-cause-other', r);
      var nameOther = sN.value === OTHER_VALUE, causeOther = sC.value === OTHER_VALUE;
      var name = nameOther ? norm(oN.value) : sN.value;
      var cause = causeOther ? norm(oC.value) : sC.value;
      var count = Number(c.value), ok = true;

      if (!sN.value) { bad(sN); ok = false; } else if (nameOther && name.length < 2) { bad(oN); ok = false; }
      if (!c.value || !isFinite(count) || count < 1 || Math.floor(count) !== count) { bad(c); ok = false; }
      if (!sC.value) { bad(sC); ok = false; } else if (causeOther && cause.length < 2) { bad(oC); ok = false; }

      if (ok) animals.push({ name: name, nameOther: nameOther, count: count, cause: cause, causeOther: causeOther });
      else animalBad = true;
    });
    if (animalBad) {
      $('#animalErr').textContent = 'กรุณาเลือกชนิดสัตว์ ระบุจำนวน (จำนวนเต็มตั้งแต่ 1 ขึ้นไป) และเลือกสาเหตุให้ครบทุกรายการ ถ้าเลือก “อื่นๆ” ต้องพิมพ์ระบุด้วย';
    }
    if (first) return { ok: false, first: first };

    var prov = state.geo[selProv.value], dist = prov.districts[selDist.value], sub = dist.subs[selSub.value];
    // ลำดับพิกัด: 1) GPS ที่ผู้ใช้กดดึง  2) พิกัดตำบลที่เลือก  3) ว่างไว้ แล้ว resolveCoord() ค้นหาจาก Nominatim ตอนบันทึก
    var pos = state.gps || state.coord;
    return {
      ok: true,
      payload: {
        firstName: v('firstName'), lastName: v('lastName'), phone: phone, foundDate: found,
        province: prov.name, district: dist.name, subdistrict: sub.name,
        lat: pos ? pos.lat : '', lng: pos ? pos.lng : '',
        animals: animals
      }
    };
  }

  /* ================================================================
   *  หน้า 1: ดึงพิกัด GPS (HTML5 Geolocation) — ผู้ใช้ต้องกดปุ่มเอง
   * ================================================================ */
  var GPS_HINT = 'ไม่บังคับ: ถ้าไม่ดึงพิกัด ระบบจะใช้ตำแหน่งโดยประมาณจากตำบลที่เลือก';
  var GPS_ERRORS = {
    1: 'ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง กรุณาอนุญาตการเข้าถึงตำแหน่งในเบราว์เซอร์หรือโทรศัพท์ แล้วกดอีกครั้ง',
    2: 'ไม่สามารถระบุตำแหน่งได้ ตรวจสอบว่าเปิด GPS/บริการตำแหน่งในอุปกรณ์แล้ว',
    3: 'ค้นหาตำแหน่งนานเกินไป กรุณาลองใหม่อีกครั้งในที่โล่ง'
  };
  var btnGps = $('#btnGps'), btnGpsClear = $('#btnGpsClear');

  function setGpsStatus(msg, kind) {
    var el = $('#gpsStatus');
    el.textContent = msg;
    el.className = 'hint' + (kind ? ' is-' + kind : '');
  }

  function clearGps() {
    state.gps = null;
    $('#gpsLat').value = '';
    $('#gpsLng').value = '';
    btnGpsClear.hidden = true;
    btnGps.textContent = '📌 ดึงพิกัดปัจจุบัน (GPS)';
    setGpsStatus(GPS_HINT);
  }

  function fetchGps() {
    if (!('geolocation' in navigator)) {
      setGpsStatus('อุปกรณ์หรือเบราว์เซอร์นี้ไม่รองรับการดึงพิกัด ระบบจะใช้ตำแหน่งตามตำบลที่เลือกแทน', 'error');
      return;
    }
    if (window.isSecureContext === false) {
      setGpsStatus('การดึงพิกัดต้องเปิดผ่านลิงก์ https เท่านั้น ระบบจะใช้ตำแหน่งตามตำบลที่เลือกแทน', 'error');
      return;
    }

    btnGps.disabled = true;
    btnGps.textContent = 'กำลังค้นหาตำแหน่ง…';
    setGpsStatus('กรุณากด “อนุญาต” เมื่อเบราว์เซอร์ขอสิทธิ์เข้าถึงตำแหน่ง');

    navigator.geolocation.getCurrentPosition(function (pos) {
      var lat = Number(pos.coords.latitude.toFixed(6));
      var lng = Number(pos.coords.longitude.toFixed(6));
      btnGps.disabled = false;
      // เซิร์ฟเวอร์รับเฉพาะพิกัดในประเทศไทย จึงตรวจฝั่งผู้ใช้ก่อนเพื่อไม่ให้ค่าถูกทิ้งเงียบๆ
      if (lat < 4 || lat > 22 || lng < 96 || lng > 107) {
        clearGps();
        setGpsStatus('พิกัดที่ได้อยู่นอกประเทศไทย จึงไม่นำไปใช้ ระบบจะใช้ตำแหน่งตามตำบลที่เลือกแทน', 'error');
        return;
      }
      state.gps = { lat: lat, lng: lng, accuracy: Math.round(pos.coords.accuracy || 0) };
      $('#gpsLat').value = lat.toFixed(6);
      $('#gpsLng').value = lng.toFixed(6);
      btnGpsClear.hidden = false;
      btnGps.textContent = '📌 ดึงพิกัดใหม่อีกครั้ง';
      setGpsStatus('ดึงพิกัดสำเร็จ' + (state.gps.accuracy ? ' (คลาดเคลื่อนประมาณ ±' + nf.format(state.gps.accuracy) + ' เมตร)' : '') + ' ระบบจะบันทึกพิกัดนี้', 'ok');
    }, function (err) {
      btnGps.disabled = false;
      btnGps.textContent = state.gps ? '📌 ดึงพิกัดใหม่อีกครั้ง' : '📌 ดึงพิกัดปัจจุบัน (GPS)';
      var msg = GPS_ERRORS[err && err.code] || 'ดึงพิกัดไม่สำเร็จ';
      setGpsStatus(msg + (state.gps ? '' : ' (ระบบจะใช้ตำแหน่งตามตำบลที่เลือกแทน)'), 'error');
    }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
  }
  btnGps.addEventListener('click', fetchGps);
  btnGpsClear.addEventListener('click', clearGps);

  /* ถ้าตำบลที่เลือกไม่มีพิกัดในชุดข้อมูล (เช่น กรุงเทพฯ ทั้งหมด) ให้ค้นหาพิกัดจาก OpenStreetMap Nominatim */
  var BKK_CENTER = { lat: 13.7563, lng: 100.5018 };
  function geocodeOne(q) {
    var ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 6000);
    return fetch('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=th&accept-language=th&q=' + encodeURIComponent(q),
      ctrl ? { signal: ctrl.signal } : undefined)
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (a) { return a && a[0] ? { lat: Number(a[0].lat), lng: Number(a[0].lon) } : null; })
      .catch(function () { return null; })
      .then(function (v) { clearTimeout(timer); return v; });
  }
  function resolveCoord(p) {
    if (p.lat !== '' && p.lng !== '') return Promise.resolve(p);
    var isBkk = p.province === 'กรุงเทพมหานคร';
    var queries = [
      p.subdistrict + ' ' + p.district + ' ' + p.province,
      p.district + ' ' + p.province,
      p.province
    ];
    return queries.reduce(function (chain, q) {
      return chain.then(function (found) { return found || geocodeOne(q); });
    }, Promise.resolve(null)).then(function (c) {
      if (!c && isBkk) c = BKK_CENTER;
      if (c) { p.lat = c.lat; p.lng = c.lng; }
      return p;
    });
  }

  function resetForm() {
    form.reset();
    FORM_FIELDS.forEach(clearErr);
    $('#animalErr').textContent = '';
    $('#foundDate').value = todayStr();
    state.coord = null;
    clearGps();
    if (state.geo) {
      resetSelect(selDist, 'เลือกอำเภอ/เขต', true);
      resetSelect(selSub, 'เลือกตำบล/แขวง', true);
    }
    animalList.innerHTML = '';
    addAnimalRow(false);
    refreshCombos();
  }
  $('#btnReset').addEventListener('click', resetForm);

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var r = collect();
    if (!r.ok) { r.first.focus(); return; }

    var btn = $('#btnSubmit');
    btn.disabled = true;
    Swal.fire({ title: 'กำลังบันทึก…', allowOutsideClick: false, allowEscapeKey: false, didOpen: function () { Swal.showLoading(); } });

    resolveCoord(r.payload).then(function (payload) { return api('saveReport', payload); }).then(function (res) {
      return Swal.fire({
        icon: 'success', title: 'บันทึกสำเร็จ',
        html: 'รหัสรายงาน <b>' + esc(res.id) + '</b><br>ข้อมูลถูกส่งไปยังแดชบอร์ดแล้ว',
        confirmButtonText: 'ตกลง', confirmButtonColor: PINE
      }).then(function () {
        resetForm();
        state.sig = ''; // บังคับให้แดชบอร์ดโหลดข้อมูลใหม่ครั้งถัดไป
      });
    }).catch(function (err) {
      Swal.fire({
        icon: 'error', title: 'บันทึกไม่สำเร็จ',
        text: (err && err.message) || 'กรุณาลองใหม่อีกครั้ง',
        confirmButtonText: 'ปิด', confirmButtonColor: PINE
      });
    }).then(function () { btn.disabled = false; });
  });

  /* ================================================================
   *  หน้า 2: โหลดข้อมูล + ตัวกรอง
   * ================================================================ */
  function setLive(ok, msg) {
    $('#liveDot').classList.toggle('is-off', !ok);
    if (ok) {
      var n = new Date();
      $('#liveText').textContent = 'อัปเดตล่าสุด ' + pad(n.getHours()) + ':' + pad(n.getMinutes()) + ':' + pad(n.getSeconds()) + ' (รีเฟรชอัตโนมัติทุก 30 วินาที)';
    } else {
      $('#liveText').textContent = 'เชื่อมต่อไม่ได้: ' + (msg || 'ไม่ทราบสาเหตุ') + ' (จะลองใหม่อัตโนมัติ)';
    }
  }

  // ดึงข้อมูลสาธารณะ + (ถ้าล็อกอินเจ้าหน้าที่) ข้อมูลส่วนบุคคล/สิทธิ์ดำเนินการของจังหวัดที่ดูแล
  function fetchReports() {
    return api('getReports').then(function (list) {
      if (!state.staff) return list;
      return api('staffReports').then(function (extra) {
        var m = {};
        extra.forEach(function (x) { m[x.id] = x; });
        list.forEach(function (r) { if (m[r.id]) r.staff = m[r.id]; });
        return list;
      }, function (err) {
        if (err && err.status === 401) staffExpired();
        return list;
      });
    });
  }

  function loadReports(silent) {
    var btn = $('#btnRefresh');
    btn.classList.add('is-spin');
    return fetchReports().then(function (list) {
      list.forEach(function (r) {
        r.reportedDate = r.ts.slice(0, 10);
        r.time = r.ts.slice(11, 19);
        r.date = r.found || r.reportedDate; // ใช้ "วันที่พบ" เป็นหลักในการกรอง/กราฟ
        r.animals.forEach(function (a) { a.cause = a.cause || r.cause || 'ไม่ระบุ'; });
      });
      var sum = list.reduce(function (s, r) { return s + r.total; }, 0);
      var stSig = list.map(function (r) { return r.status === 'done' ? 'd' : r.status === 'in_progress' ? 'p' : 'n'; }).join('');
      var sig = list.length + '|' + (list.length ? list[list.length - 1].id : '') + '|' + sum + '|' + stSig + '|' + (state.staff ? state.staff.name : '');
      var prevLen = state.reports.length, had = state.loaded;
      state.loaded = true;
      if (sig !== state.sig) {
        state.sig = sig;
        state.reports = list;
        var keepPage = state.page;
        applyFilters(!had);
        if (had) { state.page = keepPage; renderTable(); } // รีเฟรชอัตโนมัติ/กดสถานะแล้ว ไม่เด้งกลับหน้า 1
        if (silent && had && list.length > prevLen) toast.fire({ icon: 'info', title: 'มีรายงานใหม่ ' + (list.length - prevLen) + ' รายการ' });
      }
      setLive(true);
    }).catch(function (e) {
      setLive(false, e.message);
    }).then(function () { btn.classList.remove('is-spin'); });
  }

  function getRange() {
    var from = $('#dateFrom').value, to = $('#dateTo').value;
    if (from && to && from > to) { var t = from; from = to; to = t; }
    return { from: from, to: to };
  }

  function applyFilters(fitMap) {
    var rg = getRange(), st = $('#statusFilter').value;
    state.filtered = state.reports.filter(function (r) {
      return (!rg.from || r.date >= rg.from) && (!rg.to || r.date <= rg.to) && (!st || r.status === st);
    }).sort(function (a, b) { return b.date.localeCompare(a.date) || b.ts.localeCompare(a.ts); });
    state.page = 1;
    renderAll(fitMap);
  }

  function setPreset(key) {
    var today = new Date(), from = '';
    if (key === 'today') from = ymd(today);
    else if (key === '7' || key === '30') { var d = new Date(); d.setDate(d.getDate() - (Number(key) - 1)); from = ymd(d); }
    $('#dateFrom').value = from;
    $('#dateTo').value = key === 'all' ? '' : ymd(today);
    markPreset(key);
    applyFilters(true);
  }
  function markPreset(key) {
    $$('#presets button').forEach(function (b) { b.classList.toggle('is-active', b.dataset.preset === key); });
  }
  $('#presets').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (b) setPreset(b.dataset.preset);
  });
  ['dateFrom', 'dateTo'].forEach(function (id) {
    $('#' + id).addEventListener('change', function () { markPreset(''); applyFilters(true); });
  });
  $('#statusFilter').addEventListener('change', function () { applyFilters(true); });
  $('#btnRefresh').addEventListener('click', function () { loadReports(false); });

  /* ================================================================
   *  หน้า 2: สรุปตัวเลข
   * ================================================================ */
  function causesOf(r) {
    var seen = {}, out = [];
    r.animals.forEach(function (a) {
      var c = norm(a.cause) || 'ไม่ระบุ';
      if (!seen[c]) { seen[c] = 1; out.push(c); }
    });
    return out;
  }

  function aggregate(list) {
    var species = {}, cause = {}, prov = {}, total = 0;
    list.forEach(function (r) {
      total += r.total;
      prov[r.province] = 1;
      causesOf(r).forEach(function (c) { cause[c] = (cause[c] || 0) + 1; }); // นับ 1 ครั้งต่อรายงาน
      r.animals.forEach(function (a) { var k = norm(a.name); species[k] = (species[k] || 0) + a.count; });
    });
    var spEntries = Object.keys(species).map(function (k) { return [k, species[k]]; })
      .sort(function (a, b) { return b[1] - a[1]; });
    var topCause = Object.keys(cause).sort(function (a, b) { return cause[b] - cause[a]; })[0];
    return {
      total: total, species: spEntries, provinces: Object.keys(prov).length,
      topCause: topCause, topCauseN: topCause ? cause[topCause] : 0, count: list.length
    };
  }

  function renderKpis(agg) {
    $('#kReports').textContent = nf.format(agg.count);
    $('#kTotal').textContent = nf.format(agg.total);
    $('#kSpecies').textContent = nf.format(agg.species.length);
    $('#kProv').textContent = nf.format(agg.provinces);
    var c = $('#kCause');
    c.textContent = agg.topCause || '-';
    c.title = agg.topCause || '';
    $('#kCauseN').textContent = agg.topCause ? '(' + nf.format(agg.topCauseN) + ' รายงาน)' : '';
  }

  /* ================================================================
   *  หน้า 2: แผนที่ (Leaflet) — โหมดจุดแจ้งเหตุ / Heatmap รายจังหวัด
   * ================================================================ */
  var TH_CENTER = [13.2, 101];

  function initMap() {
    if (state.map) { setTimeout(function () { state.map.invalidateSize(); }, 50); return; }
    state.map = L.map('map', { scrollWheelZoom: false }).setView(TH_CENTER, 6);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(state.map);
    state.layer = L.layerGroup().addTo(state.map);
    state.map.on('click', function () { state.map.scrollWheelZoom.enable(); });
    state.map.on('mouseout', function () { state.map.scrollWheelZoom.disable(); });
    setTimeout(function () { state.map.invalidateSize(); renderMap(true); }, 50);
  }

  function popupHtml(r) {
    var lines = r.animals.map(function (a) {
      return esc(a.name) + ' ' + nf.format(a.count) + ' ตัว <span style="color:#6F7F79">(' + esc(a.cause) + ')</span>';
    }).join('<br>');
    return '<strong>' + esc(r.subdistrict) + '</strong><br>' + esc(r.district) + ', ' + esc(r.province) +
      '<br>' + lines + '<br><strong style="color:' + ALERT + '">รวม ' + nf.format(r.total) + ' ตัว</strong>' +
      '<br><span style="color:#6F7F79">พบเมื่อ ' + thaiDate(r.date) + '</span>' +
      '<br>สถานะ: <strong>' + statusOf(r).label + '</strong>';
  }

  /* ---------- Heatmap รายจังหวัด: ฟ้า = น้อย, เหลือง = กลาง, แดง = มาก ---------- */
  function heatColor(t) {
    t = Math.max(0, Math.min(1, t));
    for (var i = 1; i < HEAT_STOPS.length; i++) {
      if (t <= HEAT_STOPS[i][0]) {
        var a = HEAT_STOPS[i - 1], b = HEAT_STOPS[i];
        var k = (t - a[0]) / (b[0] - a[0]);
        var c = [0, 1, 2].map(function (j) { return Math.round(a[1][j] + (b[1][j] - a[1][j]) * k); });
        return 'rgb(' + c.join(',') + ')';
      }
    }
    return 'rgb(' + HEAT_STOPS[HEAT_STOPS.length - 1][1].join(',') + ')';
  }

  function computeProvStats() {
    var st = {}, max = 0;
    state.filtered.forEach(function (r) {
      var s = st[r.province] || (st[r.province] = { reports: 0, animals: 0 });
      s.reports += 1;
      s.animals += r.total;
      if (s.animals > max) max = s.animals;
    });
    state.provStats = st;
    state.heatMax = max || 1;
  }

  function heatStyle(f) {
    var s = state.provStats[f.properties.pro_th];
    var v = s ? s.animals : 0;
    // ใช้รากที่สองเพื่อให้จังหวัดที่มีจำนวนปานกลางไม่จมเป็นสีฟ้าเกือบหมด
    return {
      fillColor: v > 0 ? heatColor(Math.sqrt(v / state.heatMax)) : HEAT_ZERO,
      fillOpacity: 0.85, color: '#FFFFFF', weight: 1
    };
  }

  function heatTip(name) {
    var s = state.provStats[name];
    return '<strong>' + esc(name) + '</strong><br>' +
      (s ? nf.format(s.reports) + ' รายงาน, ' + nf.format(s.animals) + ' ตัว' : 'ยังไม่มีรายงาน');
  }

  function legendHtml() {
    return '<b>จำนวนสัตว์ตาย (ตัว)</b><div class="heat-legend__bar"></div>' +
      '<div class="heat-legend__labels"><span>น้อย</span><span>มาก (' + nf.format(state.heatMax) + ')</span></div>' +
      '<div class="heat-legend__zero"><i></i>ไม่มีรายงาน</div>';
  }

  function ensureProvinceGeo() {
    if (state.heatLayer) return Promise.resolve(true);
    if (state.heatLoading) return state.heatLoading;
    var i = 0;
    function attempt() {
      if (i >= PROVINCE_GEO_URLS.length) return Promise.resolve(false);
      return fetch(PROVINCE_GEO_URLS[i++])
        .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(function (gj) {
          state.heatLayer = L.geoJSON(gj, {
            style: heatStyle,
            onEachFeature: function (f, layer) {
              layer.bindTooltip(function () { return heatTip(f.properties.pro_th); }, { sticky: true });
            }
          });
          return true;
        })
        .catch(attempt);
    }
    state.heatLoading = attempt().then(function (ok) { state.heatLoading = null; return ok; });
    return state.heatLoading;
  }

  function updateHeat() {
    if (state.heatLayer) state.heatLayer.setStyle(heatStyle);
    if (state.heatLegend) state.heatLegend.update();
  }

  function setMapMode(mode, fit) {
    state.mapMode = mode;
    $$('#mapMode button').forEach(function (b) { b.classList.toggle('is-active', b.dataset.mode === mode); });
    if (!state.map) return;

    if (mode === 'heat') {
      $('#mapNote').textContent = 'กำลังโหลดเส้นแบ่งจังหวัด…';
      ensureProvinceGeo().then(function (ok) {
        if (state.mapMode !== 'heat') return;
        if (!ok) {
          toast.fire({ icon: 'error', title: 'โหลดเส้นแบ่งจังหวัดไม่สำเร็จ' });
          setMapMode('points', true);
          return;
        }
        state.map.removeLayer(state.layer);
        computeProvStats();
        state.heatLayer.addTo(state.map);
        if (!state.heatLegend) {
          state.heatLegend = L.control({ position: 'bottomright' });
          state.heatLegend.onAdd = function () { this._div = L.DomUtil.create('div', 'heat-legend'); this._div.innerHTML = legendHtml(); return this._div; };
          state.heatLegend.update = function () { if (this._div) this._div.innerHTML = legendHtml(); };
        }
        state.heatLegend.addTo(state.map);
        updateHeat();
        state.map.fitBounds(state.heatLayer.getBounds(), { padding: [10, 10] });
        $('#mapNote').textContent = 'สีแปรตามจำนวนสัตว์ตายรายจังหวัด: ฟ้า = น้อย, แดง = มาก';
      });
    } else {
      if (state.heatLayer) state.map.removeLayer(state.heatLayer);
      if (state.heatLegend) state.heatLegend.remove();
      state.layer.addTo(state.map);
      renderMap(!!fit);
    }
  }
  $('#mapMode').addEventListener('click', function (e) {
    var b = e.target.closest('button');
    if (b && b.dataset.mode !== state.mapMode) setMapMode(b.dataset.mode, true);
  });

  function renderMap(fit) {
    computeProvStats();
    if (!state.map) return;
    state.layer.clearLayers();
    state.markers = {};
    var pts = [], missing = 0;
    state.filtered.forEach(function (r) {
      if (r.lat == null || r.lng == null) { missing++; return; }
      var radius = Math.min(36, 7 + Math.sqrt(r.total) * 1.2);
      // วงกลมโปร่งแสง: จุดที่ซ้อนทับกันจะเข้มขึ้นเอง บอกความหนาแน่นของเหตุ
      var m = L.circleMarker([r.lat, r.lng], { radius: radius, color: ALERT, weight: 1.5, fillColor: ALERT, fillOpacity: 0.3 })
        .bindPopup(popupHtml(r)).addTo(state.layer);
      state.markers[r.id] = m;
      pts.push([r.lat, r.lng]);
    });

    if (state.mapMode === 'heat') {
      updateHeat();
      return;
    }
    if (fit) {
      if (pts.length) state.map.fitBounds(pts, { padding: [40, 40], maxZoom: 11 });
      else state.map.setView(TH_CENTER, 6);
    }
    $('#mapNote').textContent = 'ขนาดวงกลมแปรตามจำนวนสัตว์ที่ตาย' +
      (missing ? ' (' + nf.format(missing) + ' รายการไม่มีพิกัด)' : '');
  }

  /* ================================================================
   *  หน้า 2: กราฟ (Chart.js)
   * ================================================================ */
  Chart.defaults.font.family = "'IBM Plex Sans Thai', 'Noto Sans Thai', system-ui, sans-serif";
  Chart.defaults.font.size = 12.5;
  Chart.defaults.color = '#4A5B55';

  function upsertChart(key, canvasId, config) {
    if (state.charts[key]) { state.charts[key].destroy(); }
    state.charts[key] = new Chart($('#' + canvasId), config);
  }

  function speciesColorMap(entries) {
    var map = {};
    entries.slice(0, PALETTE.length).forEach(function (e, i) { map[e[0]] = PALETTE[i]; });
    return map;
  }
  var colorOf = function (map, name) { return map[name] || OTHER_COLOR; };

  function renderSpeciesChart(agg, cmap) {
    var top = agg.species.slice(0, 8);
    upsertChart('species', 'chartSpecies', {
      type: 'bar',
      data: {
        labels: top.map(function (e) { return e[0]; }),
        datasets: [{ data: top.map(function (e) { return e[1]; }), backgroundColor: top.map(function (e) { return colorOf(cmap, e[0]); }), borderRadius: 4, maxBarThickness: 28 }]
      },
      options: {
        indexAxis: 'y', responsive: true, maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: function (c) {
            var pct = agg.total ? (c.parsed.x / agg.total * 100).toFixed(1) : 0;
            return nf.format(c.parsed.x) + ' ตัว (' + pct + '%)';
          } } }
        },
        scales: {
          x: { beginAtZero: true, grid: { color: '#EDF1EF' }, ticks: { callback: function (v) { return nf.format(v); } } },
          y: { grid: { display: false } }
        }
      }
    });
  }

  function areaKey(r) {
    if (state.areaLevel === 'province') return r.province;
    if (state.areaLevel === 'district') return r.district + ' (' + r.province + ')';
    return r.subdistrict + ' (' + r.district + ')';
  }

  function renderAreaChart(agg, cmap) {
    var areas = {};
    state.filtered.forEach(function (r) {
      var k = areaKey(r);
      var a = areas[k] || (areas[k] = { total: 0, by: {} });
      r.animals.forEach(function (x) {
        var n = norm(x.name);
        var g = cmap[n] ? n : OTHER_LABEL;
        a.by[g] = (a.by[g] || 0) + x.count;
        a.total += x.count;
      });
    });
    var top = Object.keys(areas).sort(function (a, b) { return areas[b].total - areas[a].total; }).slice(0, 10);
    var groups = agg.species.slice(0, PALETTE.length).map(function (e) { return e[0]; });
    if (agg.species.length > PALETTE.length) groups.push(OTHER_LABEL);

    upsertChart('area', 'chartArea', {
      type: 'bar',
      data: {
        labels: top,
        datasets: groups.map(function (g) {
          return {
            label: g,
            data: top.map(function (k) { return areas[k].by[g] || 0; }),
            backgroundColor: g === OTHER_LABEL ? OTHER_COLOR : cmap[g],
            maxBarThickness: 26
          };
        })
      },
      options: {
        indexAxis: 'y', responsive: true, maintainAspectRatio: false,
        plugins: {
          legend: { position: 'bottom', labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true } },
          tooltip: { callbacks: { label: function (c) { return c.dataset.label + ': ' + nf.format(c.parsed.x) + ' ตัว'; } } }
        },
        scales: {
          x: { stacked: true, beginAtZero: true, grid: { color: '#EDF1EF' }, ticks: { callback: function (v) { return nf.format(v); } } },
          y: { stacked: true, grid: { display: false } }
        }
      }
    });
  }

  function addDays(s, n) {
    var p = s.split('-');
    var d = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]) + n));
    return d.toISOString().slice(0, 10);
  }
  function diffDays(a, b) {
    var pa = a.split('-'), pb = b.split('-');
    return Math.round((Date.UTC(+pb[0], +pb[1] - 1, +pb[2]) - Date.UTC(+pa[0], +pa[1] - 1, +pa[2])) / 86400000);
  }

  function renderTrendChart() {
    var list = state.filtered, labels = [], values = [], monthly = false;
    if (list.length) {
      var dates = list.map(function (r) { return r.date; }).sort();
      var min = dates[0], max = dates[dates.length - 1];
      monthly = diffDays(min, max) > 92;
      var sums = {};
      list.forEach(function (r) {
        var k = monthly ? r.date.slice(0, 7) : r.date;
        sums[k] = (sums[k] || 0) + r.total;
      });
      if (monthly) {
        var y = Number(min.slice(0, 4)), m = Number(min.slice(5, 7)), ey = Number(max.slice(0, 4)), em = Number(max.slice(5, 7));
        while (y < ey || (y === ey && m <= em)) {
          var key = y + '-' + pad(m);
          labels.push(pad(m) + '/' + (y + 543)); values.push(sums[key] || 0);
          if (++m > 12) { m = 1; y++; }
        }
      } else {
        for (var d = min; d <= max; d = addDays(d, 1)) {
          labels.push(d.slice(8, 10) + '/' + d.slice(5, 7)); values.push(sums[d] || 0);
        }
      }
    }
    $('#trendNote').textContent = monthly ? 'จำนวนสัตว์ตายรวมต่อเดือน' : 'จำนวนสัตว์ตายรวมต่อวัน';
    upsertChart('trend', 'chartTrend', {
      type: 'line',
      data: {
        labels: labels,
        datasets: [{
          data: values, borderColor: ALERT, backgroundColor: 'rgba(179,56,44,.12)', fill: true,
          tension: 0.25, pointRadius: values.length > 40 ? 0 : 3, pointBackgroundColor: ALERT, borderWidth: 2
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: false }, tooltip: { callbacks: { label: function (c) { return nf.format(c.parsed.y) + ' ตัว'; } } } },
        scales: {
          x: { grid: { display: false }, ticks: { maxTicksLimit: 8, maxRotation: 0 } },
          y: { beginAtZero: true, grid: { color: '#EDF1EF' }, ticks: { callback: function (v) { return nf.format(v); } } }
        }
      }
    });
  }

  $('#areaLevel').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    state.areaLevel = b.dataset.level;
    $$('#areaLevel button').forEach(function (x) { x.classList.toggle('is-active', x === b); });
    var agg = aggregate(state.filtered);
    renderAreaChart(agg, speciesColorMap(agg.species));
  });

  /* ================================================================
   *  หน้า 2: ตาราง + แบ่งหน้า
   * ================================================================ */
  function statusBadge(r) {
    var s = statusOf(r);
    return '<span class="st ' + s.cls + '">' + s.label + '</span>';
  }
  // คอลัมน์เฉพาะเจ้าหน้าที่: ผู้แจ้ง/เบอร์โทร + ปุ่มดำเนินการ (ไม่เคยถูกนำไปใส่ใน Excel)
  function staffCells(r) {
    var x = r.staff;
    if (!x) return '<td class="staff-col"><span class="sub">—</span></td><td class="staff-col"><span class="sub">นอกเขตที่ดูแล</span></td>';
    var tel = String(x.phone || '').replace(/[^\d+]/g, '');
    var contact = esc(x.name || '-') +
      (x.phone ? '<a class="tel" href="tel:' + esc(tel) + '">' + esc(x.phone) + '</a>' : '<span class="sub">ไม่มีเบอร์ (รายงานเก่า)</span>');
    var act;
    if (r.status === 'done') {
      act = '<span class="sub">ปิดงานโดย ' + esc(x.completedBy || '-') + '</span>';
    } else if (!x.canAct) {
      act = '<span class="sub">ดูอย่างเดียว' + (x.acceptedBy ? '<br>รับงานโดย ' + esc(x.acceptedBy) : '') + '</span>';
    } else if (r.status === 'new') {
      act = '<button type="button" class="btn btn--primary btn--sm" data-act="accept" data-id="' + esc(r.id) + '">รับงาน</button>';
    } else {
      act = '<button type="button" class="btn btn--outline btn--sm" data-act="complete" data-id="' + esc(r.id) + '">ดำเนินการเรียบร้อย</button>' +
        (x.acceptedBy ? '<span class="sub">รับงานโดย ' + esc(x.acceptedBy) + '</span>' : '');
    }
    return '<td class="staff-col">' + contact + '</td><td class="staff-col">' + act + '</td>';
  }

  function renderTable() {
    var list = state.filtered, total = list.length;
    var pages = Math.max(1, Math.ceil(total / state.pageSize));
    if (state.page > pages) state.page = pages;
    var start = (state.page - 1) * state.pageSize;
    var slice = list.slice(start, start + state.pageSize);
    var rg = getRange();
    var rangeTxt = (rg.from || rg.to)
      ? 'วันที่พบ ' + (rg.from ? thaiDate(rg.from) : 'เริ่มต้น') + ' ถึง ' + (rg.to ? thaiDate(rg.to) : 'ปัจจุบัน')
      : 'ทุกช่วงเวลา';
    $('#tableNote').textContent = rangeTxt + ': ' + nf.format(total) + ' รายการ';

    var staffMode = !!state.staff, cols = staffMode ? 8 : 6;
    $('.tbl').classList.toggle('is-staff', staffMode);

    if (!state.loaded) {
      $('#tbody').innerHTML = '<tr><td class="empty" colspan="' + cols + '">กำลังโหลดข้อมูล…</td></tr>';
    } else if (!slice.length) {
      $('#tbody').innerHTML = '<tr><td class="empty" colspan="' + cols + '">ไม่พบรายงานในช่วงวันที่นี้ ลองขยายช่วงวันที่หรือเลือก “ทั้งหมด”</td></tr>';
    } else {
      $('#tbody').innerHTML = slice.map(function (r) {
        var chips = r.animals.map(function (a) {
          return '<span class="chip" title="สาเหตุ: ' + esc(a.cause) + '">' + esc(a.name) + ' ' + nf.format(a.count) + '</span>';
        }).join('');
        return '<tr data-id="' + esc(r.id) + '">' +
          '<td class="when">' + thaiDate(r.date) + '<span class="sub">แจ้งเมื่อ ' + thaiDate(r.reportedDate) + ' ' + r.time.slice(0, 5) + ' น.</span></td>' +
          '<td>' + esc(r.subdistrict) + '<span class="sub">' + esc(r.district) + ', ' + esc(r.province) + '</span></td>' +
          '<td><div class="chips">' + chips + '</div></td>' +
          '<td class="num">' + nf.format(r.total) + '</td>' +
          '<td>' + esc(causesOf(r).join(', ')) + '</td>' +
          '<td>' + statusBadge(r) + (statusTime(r) ? '<span class="sub">' + statusTime(r) + '</span>' : '') + '</td>' +
          (staffMode ? staffCells(r) : '') + '</tr>';
      }).join('');
    }
    $('#pagerInfo').textContent = total
      ? 'แสดง ' + nf.format(start + 1) + '–' + nf.format(start + slice.length) + ' จาก ' + nf.format(total)
      : '';
    $('#pgPrev').disabled = state.page <= 1;
    $('#pgNext').disabled = state.page >= pages;
  }
  $('#pgPrev').addEventListener('click', function () { state.page--; renderTable(); });
  $('#pgNext').addEventListener('click', function () { state.page++; renderTable(); });

  // คลิกแถวในตาราง -> เลื่อนไปที่แผนที่และเปิดป้ายข้อมูลของจุดนั้น
  $('#tbody').addEventListener('click', function (e) {
    var actBtn = e.target.closest('button[data-act]');
    if (actBtn) { changeStatus(actBtn.dataset.id, actBtn.dataset.act); return; }
    if (e.target.closest('a')) return; // กดเบอร์โทรไม่ต้องเลื่อนแผนที่
    var tr = e.target.closest('tr[data-id]'); if (!tr) return;
    if (!state.markers[tr.dataset.id]) { toast.fire({ icon: 'info', title: 'รายการนี้ไม่มีพิกัดบนแผนที่' }); return; }
    if (state.mapMode !== 'points') setMapMode('points', false); // สลับโหมดก่อน เพราะจะสร้างจุดใหม่
    var m = state.markers[tr.dataset.id];
    $('#map').scrollIntoView({ behavior: 'smooth', block: 'center' });
    state.map.flyTo(m.getLatLng(), Math.max(state.map.getZoom(), 11), { duration: 0.8 });
    m.openPopup();
  });

  /* ================================================================
   *  หน้า 2: Export Excel (เฉพาะข้อมูลที่กรองแล้ว — ไม่มีชื่อ/เบอร์โทรผู้แจ้ง แม้เจ้าหน้าที่ล็อกอินอยู่)
   * ================================================================ */
  $('#btnExport').addEventListener('click', function () {
    var list = state.filtered;
    if (!list.length) {
      Swal.fire({ icon: 'info', title: 'ไม่มีข้อมูลให้ส่งออก', text: 'ไม่พบรายงานในช่วงวันที่ที่เลือก', confirmButtonText: 'ตกลง', confirmButtonColor: PINE });
      return;
    }
    var ordered = list.slice().sort(function (a, b) { return a.date.localeCompare(b.date) || a.ts.localeCompare(b.ts); });

    var sheet1 = ordered.map(function (r) {
      return {
        'รหัสรายงาน': r.id, 'วันที่พบ': thaiDate(r.date), 'วันที่แจ้ง': thaiDate(r.reportedDate), 'เวลาที่แจ้ง': r.time,
        'จังหวัด': r.province, 'อำเภอ/เขต': r.district, 'ตำบล/แขวง': r.subdistrict,
        'ละติจูด': r.lat, 'ลองจิจูด': r.lng,
        'ชนิดสัตว์ (สรุป)': r.animals.map(function (a) { return a.name + ' ' + a.count; }).join(', '),
        'จำนวนรวม (ตัว)': r.total, 'สาเหตุ': causesOf(r).join(', '),
        'สถานะ': statusOf(r).label
      };
    });
    var sheet2 = [];
    ordered.forEach(function (r) {
      r.animals.forEach(function (a) {
        sheet2.push({
          'รหัสรายงาน': r.id, 'วันที่พบ': thaiDate(r.date),
          'จังหวัด': r.province, 'อำเภอ/เขต': r.district, 'ตำบล/แขวง': r.subdistrict,
          'ชนิดสัตว์': a.name, 'จำนวน (ตัว)': a.count, 'สาเหตุ': a.cause
        });
      });
    });

    var ws1 = XLSX.utils.json_to_sheet(sheet1), ws2 = XLSX.utils.json_to_sheet(sheet2);
    ws1['!cols'] = [14, 12, 12, 10, 16, 18, 18, 11, 11, 36, 14, 28, 20].map(function (w) { return { wch: w }; });
    ws2['!cols'] = [14, 12, 16, 18, 18, 18, 12, 24].map(function (w) { return { wch: w }; });
    var wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws1, 'รายงานแจ้งเหตุ');
    XLSX.utils.book_append_sheet(wb, ws2, 'แยกตามชนิดสัตว์');

    var rg = getRange();
    var name = 'animal-death-report_' + (rg.from || 'all') + '_to_' + (rg.to || 'all') + '.xlsx';
    XLSX.writeFile(wb, name);
    toast.fire({ icon: 'success', title: 'ส่งออก ' + nf.format(list.length) + ' รายการแล้ว' });
  });

  /* ================================================================
   *  หน้า 3: ติดต่อเจ้าหน้าที่
   * ================================================================ */
  var allContacts = [];
  var PHONE_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
  var contactSel = $('#contactProvince');
  var contactHint = function (msg) { return '<p style="color: var(--ink-3);">' + msg + '</p>'; };

  function loadContacts() {
    $('#contactList').innerHTML = contactHint('กำลังโหลดข้อมูล...');
    api('getContacts').then(function (data) {
      allContacts = data;
      state.contactLoaded = true;
      var pSet = {};
      data.forEach(function (c) { if (c.province) pSet[c.province] = true; });
      var pList = Object.keys(pSet).sort(collator.compare);
      contactSel.innerHTML = '<option value="">เลือกจังหวัด</option>';
      pList.forEach(function (p) { contactSel.add(new Option(p, p)); });
      contactSel.disabled = false;
      $('#contactList').innerHTML = contactHint('กรุณาเลือกจังหวัดจากเมนูด้านบน เพื่อดูรายชื่อเจ้าหน้าที่');
    }).catch(function (e) {
      contactSel.innerHTML = '<option value="">โหลดข้อมูลล้มเหลว</option>';
      $('#contactList').innerHTML = '<p class="err">ไม่สามารถดึงข้อมูลได้: ' + esc(e.message) + '</p>';
    });
  }

  contactSel.addEventListener('change', function () {
    var listEl = $('#contactList');
    var selected = contactSel.value;
    if (!selected) { listEl.innerHTML = contactHint('กรุณาเลือกจังหวัดจากเมนูด้านบน เพื่อดูรายชื่อเจ้าหน้าที่'); return; }
    var rows = allContacts.filter(function (c) { return c.province === selected; });
    if (!rows.length) { listEl.innerHTML = contactHint('ไม่พบข้อมูลเจ้าหน้าที่ในจังหวัดนี้'); return; }

    // การ์ด: หน่วยงาน / ชื่อ (ไม่มีไอคอนคน) / เบอร์โทร (อยู่ติดไอคอนโทรศัพท์)
    listEl.innerHTML = rows.map(function (c) {
      var tel = String(c.phone).split(/[,\/;]|ต่อ|หรือ/)[0].replace(/[^\d+]/g, '');
      return '<div class="contact-card">' +
        '<div class="contact-agency">' + esc(c.agency) + '</div>' +
        (c.name ? '<div class="contact-name">' + esc(c.name) + '</div>' : '') +
        (c.phone ? '<a class="contact-phone" href="tel:' + esc(tel) + '">' + PHONE_ICON + '<span>' + esc(c.phone) + '</span></a>' : '') +
        '</div>';
    }).join('');
  });

  /* ================================================================
   *  เจ้าหน้าที่: เข้าสู่ระบบ / ออกจากระบบ / รับงาน / ปิดงาน
   * ================================================================ */
  function updateStaffUI() {
    var s = state.staff;
    $('#btnStaffLogin').hidden = !!s;
    $('#staffInfo').hidden = !s;
    var b = $('#staffBanner');
    if (!s) { b.hidden = true; return; }
    $('#staffName').textContent = s.name;
    $('#staffRole').textContent = s.roleLabel;
    var scope = s.role === 'central' ? 'ทุกจังหวัด' : s.provinces.join(', ');
    b.textContent = 'เข้าสู่ระบบในฐานะ ' + s.roleLabel + ' • ดูแล: ' + scope +
      (s.canAct ? '' : ' • สิทธิ์ดูข้อมูลอย่างเดียว') + ' • ชื่อและเบอร์โทรผู้แจ้งแสดงเฉพาะในตารางด้านล่าง และจะไม่ถูกส่งออก Excel';
    b.hidden = false;
  }
  function refreshAfterAuthChange() {
    state.sig = ''; // บังคับโหลดใหม่ เพื่อเพิ่ม/ลบข้อมูลเฉพาะเจ้าหน้าที่
    if (state.view === 'dashboard') loadReports(true);
  }
  function staffExpired() {
    if (!state.staff) return;
    state.staff = null;
    updateStaffUI();
    toast.fire({ icon: 'warning', title: 'หมดเวลาเข้าสู่ระบบ กรุณาเข้าสู่ระบบอีกครั้ง' });
    refreshAfterAuthChange();
  }

  function openLogin() {
    Swal.fire({
      title: 'เข้าสู่ระบบเจ้าหน้าที่',
      html: '<input id="lgUser" class="swal2-input" placeholder="ชื่อผู้ใช้" autocomplete="username" autocapitalize="none">' +
            '<input id="lgPass" type="password" class="swal2-input" placeholder="รหัสผ่าน" autocomplete="current-password">',
      focusConfirm: false, showCancelButton: true, showLoaderOnConfirm: true,
      confirmButtonText: 'เข้าสู่ระบบ', cancelButtonText: 'ยกเลิก', confirmButtonColor: PINE,
      didOpen: function () {
        $('#lgUser').focus();
        $('#lgPass').addEventListener('keydown', function (e) { if (e.key === 'Enter') Swal.clickConfirm(); });
      },
      preConfirm: function () {
        var u = $('#lgUser').value.trim(), p = $('#lgPass').value;
        if (!u || !p) { Swal.showValidationMessage('กรุณากรอกชื่อผู้ใช้และรหัสผ่าน'); return false; }
        return api('login', { username: u, password: p }).catch(function (e) {
          Swal.showValidationMessage(e.message); return false;
        });
      }
    }).then(function (r) {
      if (!r.isConfirmed || !r.value || !r.value.staff) return;
      state.staff = r.value.staff;
      updateStaffUI();
      toast.fire({ icon: 'success', title: 'เข้าสู่ระบบแล้ว' });
      if (state.view === 'dashboard') refreshAfterAuthChange(); else showView('dashboard');
      state.sig = '';
    });
  }
  $('#btnStaffLogin').addEventListener('click', openLogin);
  $('#btnStaffLogout').addEventListener('click', function () {
    api('logout').catch(function () {}).then(function () {
      state.staff = null;
      state.reports.forEach(function (r) { delete r.staff; });
      updateStaffUI();
      toast.fire({ icon: 'success', title: 'ออกจากระบบแล้ว' });
      refreshAfterAuthChange();
    });
  });

  function changeStatus(id, action) {
    var r = null;
    state.reports.forEach(function (x) { if (x.id === id) r = x; });
    if (!r || !r.staff) return;
    var accept = action === 'accept';
    Swal.fire({
      icon: 'question',
      title: accept ? 'รับงานรายงานนี้?' : 'ยืนยันว่าดำเนินการเรียบร้อยแล้ว?',
      html: '<b>' + esc(r.subdistrict) + '</b> ' + esc(r.district) + ', ' + esc(r.province) +
            '<br>รวม ' + nf.format(r.total) + ' ตัว • รหัส ' + esc(r.id) +
            '<br><span style="color:#6F7F79">สถานะจะแสดงบนแดชบอร์ดว่า “' + (accept ? STATUS.in_progress.label : STATUS.done.label) + '”</span>',
      showCancelButton: true, showLoaderOnConfirm: true,
      confirmButtonText: accept ? 'รับงาน' : 'ดำเนินการเรียบร้อย', cancelButtonText: 'ยกเลิก', confirmButtonColor: PINE,
      preConfirm: function () {
        return api('updateStatus', { id: id, action: action }).catch(function (e) {
          if (e.status === 401) { Swal.close(); staffExpired(); return false; }
          Swal.showValidationMessage(e.message); return false;
        });
      }
    }).then(function (res) {
      if (!res.isConfirmed || !res.value) return;
      toast.fire({ icon: 'success', title: accept ? 'รับงานแล้ว' : 'บันทึกว่าดำเนินการเรียบร้อยแล้ว' });
      state.sig = '';
      loadReports(true);
    });
  }

  function initAuth() {
    api('me').then(function (res) {
      if (res && res.staff) { state.staff = res.staff; updateStaffUI(); refreshAfterAuthChange(); }
    }).catch(function () {});
  }

  /* ================================================================
   *  Render all
   * ================================================================ */
  function renderAll(fitMap) {
    var agg = aggregate(state.filtered);
    var cmap = speciesColorMap(agg.species);
    renderKpis(agg);
    renderSpeciesChart(agg, cmap);
    renderAreaChart(agg, cmap);
    renderTrendChart();
    renderMap(!!fitMap);
    renderTable();
  }

  /* ================================================================
   *  Init
   * ================================================================ */
  if (!hasGAS) { seedDemo(); $('#demoBanner').hidden = false; }
  enhanceSelect(contactSel);
  updateStaffUI();
  initAuth();
  $('#foundDate').value = todayStr();
  addAnimalRow(false);
  setGpsStatus(GPS_HINT);
  loadGeo();
  renderTable();
})();
