// ===================== AUTH =====================
async function doLogin(){
  var u=document.getElementById('li-u').value.trim(), p=document.getElementById('li-p').value;
  if(!u||!p){toast('Введите логин и пароль','err');return;}
  try{
    var r=await api('auth.php',{action:'login',username:u,password:p});
    setCsrfToken(r.csrf_token||'');
    CU=r.user; nextOrderNum=r.next_order;
    await bootstrapAuthenticatedSession();
    toast('Добро пожаловать, '+CU.full_name+'!');
  }catch(e){toast(e.message||'Ошибка входа','err');}
}
async function doLogout(){await api('auth.php',{action:'logout'});location.reload();}
document.getElementById('li-p').addEventListener('keydown',function(e){if(e.key==='Enter')doLogin();});

