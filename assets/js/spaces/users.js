// ===================== ПОЛЬЗОВАТЕЛИ =====================
var allManagersList=[], usersCache={};
async function loadUsers(){
  try{
    var users=await loadUsersDirectory(true);
    allManagersList=users.filter(function(u){return u.role==='manager';});
    usersCache={}; users.forEach(function(u){usersCache[u.id]=u;});
    var addBtnHost=document.querySelector('#page-settings-users .ph .pa');
    if(addBtnHost){
      var addBtn=addBtnHost.querySelector('button');
      if(addBtn) addBtn.style.display=accessCanUi('users','create')?'':'none';
    }
    var tree=document.getElementById('users-tree');
    if(!tree) return;
    if(!users.length){
      tree.className='emp-tree';
      tree.innerHTML='<div class="emp-empty"><div class="ei">👥</div><div class="et">Нет пользователей</div><div class="es2">Добавьте первого пользователя, чтобы увидеть структуру.</div></div>';
      renderEmployeeDetails(null,'users-details','users');
      return;
    }
    tree.className='emp-tree';
    tree.innerHTML=buildEmployeesTree(users,{detailsId:'users-details',mode:'users'});
    selectEmployeeNode(empDefaultUserId(users),'users-details','users');
  }catch(e){toast(e.message,'err');}
}

function openUserModalById(id){
  openUserModal(id, usersCache[id]);
}

function deleteUserById(id){
  var u=usersCache[id]||{};
  deleteUser(id,u.username||u.full_name||'');
}

async function setDirectorById(id){
  var u=usersCache[id]||{};
  var name=u.full_name||u.username||'пользователя';
  if(!confirm('Назначить пользователя «'+name+'» директором?')) return;
  try{
    await api('users.php',{action:'set_director',id:parseInt(id,10)});
    invalidateApiCache('users');
    toast('Директор назначен ✓');
    await loadUsers();
  }catch(e){toast(e.message,'err');}
}

function openUserModal(id, userData, defaultRole){
  document.getElementById('um-id').value=id||'';
  document.getElementById('um-fn').value='';
  document.getElementById('um-un').value='';
  document.getElementById('um-pw').value='';
  document.getElementById('um-phone').value='';
  document.getElementById('um-tg').value='';
  document.getElementById('um-email').value='';
  document.getElementById('um-role').value=defaultRole||'manager';
  document.getElementById('um-managers-block').style.display='none';
  var isEdit=!!id;
  document.getElementById('um-title').textContent=isEdit?'✏️ Редактировать пользователя':'➕ Новый пользователь';
  document.getElementById('um-un').disabled=isEdit;
  document.getElementById('um-pwdhint').style.display=isEdit?'':'none';
  if(isEdit && userData){
    document.getElementById('um-fn').value=userData.full_name||'';
    document.getElementById('um-un').value=userData.username||'';
    document.getElementById('um-phone').value=userData.phone||'';
    document.getElementById('um-tg').value=userData.telegram||'';
    document.getElementById('um-email').value=userData.email||'';
    document.getElementById('um-role').value=userData.role||'manager';
    if(userData.role==='rop'){
      showManagersList(userData.manager_ids||[]);
    }
  } else {
    umRoleChange();
  }
  om('m-user');
}

function umRoleChange(){
  var role=document.getElementById('um-role').value;
  if(role==='rop'){
    showManagersList([]);
  } else {
    document.getElementById('um-managers-block').style.display='none';
  }
}

function showManagersList(selectedIds){
  selectedIds=(selectedIds||[]).map(function(id){ return String(id); });
  document.getElementById('um-managers-block').style.display='';
  var list=document.getElementById('um-managers-list');
  list.innerHTML='';
  allManagersList.forEach(function(m){
    var chk=document.createElement('label');
    chk.style.cssText='display:flex;align-items:center;gap:8px;padding:5px 4px;cursor:pointer;font-size:.85rem';
    var inp=document.createElement('input');
    inp.type='checkbox'; inp.value=m.id;
    inp.checked=selectedIds.indexOf(String(m.id))>=0;
    chk.appendChild(inp);
    chk.appendChild(document.createTextNode(m.full_name));
    list.appendChild(chk);
  });
  if(!allManagersList.length) list.innerHTML='<div style="color:var(--tx3);font-size:.82rem">Нет менеджеров</div>';
}

async function saveUser(){
  var id=document.getElementById('um-id').value;
  var full_name=document.getElementById('um-fn').value.trim();
  var username=document.getElementById('um-un').value.trim();
  var password=document.getElementById('um-pw').value;
  var role=document.getElementById('um-role').value;
  var phone=document.getElementById('um-phone').value.trim();
  var telegram=document.getElementById('um-tg').value.trim();
  var email=document.getElementById('um-email').value.trim();
  if(!full_name){toast('Введите ФИО','err');return;}
  if(!email||email.indexOf('@')<0){toast('Введите корректный email','err');return;}

  // Collect manager ids for ROP
  var manager_ids=[];
  if(role==='rop'){
    document.querySelectorAll('#um-managers-list input[type=checkbox]:checked').forEach(function(cb){
      manager_ids.push(parseInt(cb.value));
    });
    //if(!manager_ids.length){toast('Укажите хотя бы одного менеджера для РОП','err');return;}
  }

  try{
    if(id){
      await api('users.php',{action:'update',id:parseInt(id),full_name:full_name,role:role,password:password,phone:phone,telegram:telegram,email:email,manager_ids:manager_ids});
    }else{
      if(!username||!password){toast('Заполните все поля','err');return;}
      await api('users.php',{action:'create',username:username,password:password,role:role,full_name:full_name,phone:phone,telegram:telegram,email:email,manager_ids:manager_ids});
    }
    invalidateApiCache('users');
    toast('Сохранено ✓');cm('m-user');loadUsers();
  }catch(e){toast(e.message,'err');}
}

async function deleteUser(id,uname){
  if(!confirm('Удалить пользователя «'+uname+'»?'))return;
  try{
    var result=await api('users.php',{action:'delete',id:id});
    if(!result || !result.ok) throw new Error('Пользователь не был удалён');
    invalidateApiCache('users');
    await loadUsers();
    toast('Удалён');
  }catch(e){toast(e.message,'err');}
}

