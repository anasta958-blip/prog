// ===================== LAZY SCRIPT LOADER =====================
var APP_LOADED_SCRIPTS={};
var APP_LOADING_SCRIPTS={};

function loadAppScript(path){
  if(!path) return Promise.resolve();
  if(APP_LOADED_SCRIPTS[path]) return Promise.resolve();
  if(APP_LOADING_SCRIPTS[path]) return APP_LOADING_SCRIPTS[path];

  APP_LOADING_SCRIPTS[path]=new Promise(function(resolve,reject){
    var src=(window.APP_LAZY_ASSETS&&window.APP_LAZY_ASSETS[path]) ? window.APP_LAZY_ASSETS[path] : path;
    var existing=document.querySelector('script[data-lazy-script="'+path+'"]');
    if(existing){
      APP_LOADED_SCRIPTS[path]=true;
      resolve();
      return;
    }

    var script=document.createElement('script');
    script.src=src;
    script.async=false;
    script.dataset.lazyScript=path;
    script.onload=function(){
      APP_LOADED_SCRIPTS[path]=true;
      delete APP_LOADING_SCRIPTS[path];
      resolve();
    };
    script.onerror=function(){
      delete APP_LOADING_SCRIPTS[path];
      reject(new Error('\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u0441\u043a\u0440\u0438\u043f\u0442: '+path));
    };
    document.body.appendChild(script);
  });

  return APP_LOADING_SCRIPTS[path];
}

async function loadAppScripts(paths){
  for(var i=0;i<(paths||[]).length;i++){
    await loadAppScript(paths[i]);
  }
}

var KP_PAGE_SCRIPTS=[
  'assets/js/spaces/kp/state.js',
  'assets/js/spaces/kp/catalog.js',
  'assets/js/spaces/kp/builder-core.js',
  'assets/js/spaces/kp/render.js',
  'assets/js/spaces/kp/save.js'
];

var PAGE_SCRIPT_GROUPS={
  catalog:[
    'assets/js/spaces/catalog.js'
  ],
  'catalog-orders':[
    'assets/js/spaces/catalog.js'
  ],
  orders:[
    'assets/js/spaces/orders.js'
  ],
  'order-edit':[
    'assets/js/spaces/orders.js'
  ],
  'kp-company':KP_PAGE_SCRIPTS,
  'kp-clients':KP_PAGE_SCRIPTS,
  'kp-contractors':KP_PAGE_SCRIPTS,
  'kp-list':KP_PAGE_SCRIPTS,
  'kp-builder':KP_PAGE_SCRIPTS,
  employees:[
    'assets/js/shared/employees.js',
    'assets/js/spaces/users.js'
  ],
  'settings-units':[
    'assets/js/spaces/settings.js'
  ],
  'settings-suppliers':[
    'assets/js/spaces/settings.js'
  ],
  'settings-groups':[
    'assets/js/spaces/settings.js'
  ],
  'settings-users':[
    'assets/js/spaces/settings.js',
    'assets/js/shared/employees.js',
    'assets/js/spaces/users.js'
  ],
  'settings-access':[
    'assets/js/spaces/settings.js'
  ],
  'documents-builder':[
    'node_modules/jspdf/dist/jspdf.umd.min.js',
    'node_modules/jspdf-autotable/dist/jspdf.plugin.autotable.min.js',
    'assets/js/spaces/documents.js'
  ]
};

async function ensurePageScripts(page){
  await loadAppScripts(PAGE_SCRIPT_GROUPS[page]||[]);
}
