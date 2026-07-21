// ===================== API =====================
var API_CACHE={users:null};

function setCsrfToken(token){
  CSRF_TOKEN=token?String(token):'';
}

function csrfHeaders(headers){
  headers=headers||{};
  if(CSRF_TOKEN) headers['X-CSRF-Token']=CSRF_TOKEN;
  return headers;
}

function csrfFetchOptions(opts){
  opts=opts||{};
  var method=String(opts.method||'GET').toUpperCase();
  if(method!=='GET'&&method!=='HEAD'&&method!=='OPTIONS'){
    opts.headers=csrfHeaders(opts.headers||{});
  }
  return opts;
}

async function apiRequest(url,opts){
  opts=opts||{};
  opts.credentials=opts.credentials||'same-origin';
  opts=csrfFetchOptions(opts);
  var res=await fetch('api/'+url,opts),data=null;
  try{
    data=await res.json();
  }catch(_e){
    data={error:res.status===403||res.status===401?'Нет прав':'Ошибка запроса'};
  }
  var isEnvelope=data && typeof data==='object' && typeof data.ok==='boolean' && Object.prototype.hasOwnProperty.call(data,'data') && Object.prototype.hasOwnProperty.call(data,'error');
  if(!res.ok || (isEnvelope && data.ok===false)){
    var msg=(data&&data.error)?String(data.error):'Ошибка запроса';
    if(res.status===403 || res.status===401 || /forbidden|unauthorized/i.test(msg)) msg='Нет прав';
    throw new Error(msg);
  }
  return isEnvelope ? data.data : data;
}

async function apiGet(url){
  return apiRequest(url,{method:'GET'});
}

async function apiPost(url,body){
  return apiRequest(url,{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify(body||{})
  });
}

async function apiUpload(url,formData){
  return apiRequest(url,{
    method:'POST',
    body:formData
  });
}

async function api(url,body){
  return body ? apiPost(url,body) : apiGet(url);
}

function apiItems(response){
  if(response && typeof response==='object' && Array.isArray(response.items)) return response.items;
  return Array.isArray(response) ? response : [];
}

function apiPagination(response){
  return response && typeof response==='object' && response.pagination ? response.pagination : null;
}

function invalidateApiCache(key){
  if(key) API_CACHE[key]=null;
}

async function loadUsersDirectory(force){
  if(force || !Array.isArray(API_CACHE.users)){
    var rows=await apiGet('users.php?action=list');
    API_CACHE.users=Array.isArray(rows)?rows:[];
  }
  return API_CACHE.users.slice();
}
