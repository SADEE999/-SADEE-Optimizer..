import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/key_service.dart';
import '../services/optimizer_service.dart';

class UserHomeScreen extends StatefulWidget { const UserHomeScreen({super.key}); @override State<UserHomeScreen> createState()=>_UserHomeScreenState(); }
class _UserHomeScreenState extends State<UserHomeScreen> {
  static const bg=Color(0xFF050609), panel=Color(0xFF101318), green=Color(0xFF39FF88), cyan=Color(0xFF00E5FF), red=Color(0xFFFF315B), purple=Color(0xFF9C5CFF);
  final svc=OptimizerService(), keys=KeyService();
  final keyCtrl=TextEditingController();
  StreamSubscription? _progressSub; Timer? _metricsTimer; Timer? _gameTimer;
  int tab=0, gameSeconds=0; bool busy=false, cancelRequested=false, gameRunning=false, freeFireMax=false; double progress=0;
  String operation='READY'; Map<String,String> device={}; Map<String,dynamic> metrics={}; int cacheBytes=0;
  final Map<String,Map<String,dynamic>> scans={}; final Set<String> selectedPaths={}; List<Map<String,dynamic>> history=[];
  final categories=const ['downloads','large','old','duplicates','junk','empty'];

  @override void initState(){super.initState(); _load(); _progressSub=svc.progressStream.listen((e){ if(!mounted)return; setState(()=>progress=((e['progress']??0) as num).toDouble()/100); }); _metricsTimer=Timer.periodic(const Duration(seconds:3),(_)=>_refreshMetrics()); _loadHistory();}
  Future<void> _load() async { final d=await svc.getDeviceInfo(); final m=await svc.getSystemMetrics(); final c=await svc.getAppCacheBytes(); if(mounted)setState(() { device=d; metrics=m; cacheBytes=c; }); }
  Future<void> _refreshMetrics() async { final m=await svc.getSystemMetrics(); if(mounted)setState(()=>metrics=m); }
  Future<void> _loadHistory() async { try{final f=File('${(await getApplicationSupportDirectory()).path}/operation_history.json'); if(f.existsSync()) history=List<Map<String,dynamic>>.from(jsonDecode(await f.readAsString())); if(mounted)setState((){});}catch(_){}}
  Future<void> _saveHistory(String op,int scanned,int cleaned,num bytes) async { history.insert(0,{'time':DateTime.now().toIso8601String(),'operation':op,'scanned':scanned,'cleaned':cleaned,'bytes':bytes}); if(history.length>50)history=history.take(50).toList(); try{final d=await getApplicationSupportDirectory();await File('${d.path}/operation_history.json').writeAsString(jsonEncode(history));}catch(_){} if(mounted)setState((){});}
  Future<void> _scan(String category) async { if(busy)return; if(!await svc.hasAllFilesAccess()){_msg('Storage access is required for shared-storage scanning.',Colors.orange);await svc.requestAllFilesAccess();return;} setState(() { busy=true; cancelRequested=false; progress=0; operation='${_label(category).toUpperCase()} started...'; }); final r=await svc.scanFiles(category); if(!mounted)return; scans[category]=r; selectedPaths.addAll([]); setState(() { busy=false; progress=1; operation='${_label(category).toUpperCase()} completed'; }); _msg('Scanned ${r['scannedFiles']??0} files • ${_bytes(r['totalBytes'])}',green);}
  Future<void> _scanAll() async { for(final c in categories){ if(cancelRequested)break; await _scan(c); } if(mounted&&!cancelRequested)setState(()=>operation='FULL SCAN completed'); }
  Future<void> _cancel() async { cancelRequested=true; await svc.cancelScan(); if(mounted)setState(() { busy=false; operation='SCAN cancelled'; progress=0; }); }
  Future<void> _cleanSelected() async { if(busy||selectedPaths.isEmpty){_msg('Select files first.',Colors.orange);return;} final ok=await _confirm('Delete selected','Delete ${selectedPaths.length} selected items?');if(!ok)return; final before=selectedPaths.length; final result=await svc.deleteFiles(selectedPaths.toList()); final bytes=(result['bytes']??0) as num; selectedPaths.clear(); scans.clear(); await _saveHistory('SELECTED CLEAN',before,(result['deleted']??0) as int,bytes); await _load(); _msg('Cleaned ${result['deleted']??0} files • ${_bytes(bytes)}',green);}
  Future<void> _cleanCache() async { if(busy)return; setState(() { busy=true; progress=.1; operation='CACHE CLEAN started...'; }); final before=cacheBytes; final cleared=await svc.clearAppCache(); await svc.trimMemory(); await _load(); if(!mounted)return;setState(() { busy=false; progress=1; operation='CACHE CLEAN completed'; });await _saveHistory('CACHE CLEAN',1,1,cleared);_msg('App cache cleaned • ${_bytes(cleared)}',green);}
  Future<void> _ramClean() async { if(busy)return; final before=_ramPercent; setState(() { busy=true; progress=.15; operation='RAM CLEANER started...'; }); final cleared=await svc.clearAppCache(); await svc.trimMemory(); await Future.delayed(const Duration(milliseconds:300)); await _load(); if(!mounted)return; final after=_ramPercent; setState(() { busy=false; progress=1; operation='RAM CLEANER completed'; });await _saveHistory('RAM CLEANER',1,1,cleared);_msg('App-owned cleanup done • RAM ${before.toStringAsFixed(0)}% → ${after.toStringAsFixed(0)}% (Android decides system reclaim)',green);}
  Future<void> _mode(String mode) async { if(busy)return; if(mode=='PERFORMANCE'){await _ramClean();} else if(mode=='BALANCED'){setState(()=>operation='BALANCED MODE activated');_msg('Balanced mode: monitoring without forced system changes.',cyan);} else {await _refreshMetrics();setState(()=>operation='COOL DOWN monitor activated');_msg('Cool Down: monitoring temperature and thermal status.',cyan);} }
  Future<void> _oneTapOptimize() async {
    if(busy)return;
    HapticFeedback.mediumImpact();
    setState(() { busy=true; progress=.05; operation='SMART OPTIMIZE started...'; });
    try {
      for (final step in [
        'Checking device health...',
        'Cleaning app cache...',
        'Refreshing RAM metrics...',
        'Checking thermal state...',
        'Preparing gaming mode...',
      ]) {
        if(cancelRequested) break;
        setState(()=>operation=step);
        await Future.delayed(const Duration(milliseconds:350));
        if(step=='Cleaning app cache...') { await svc.clearAppCache(); await svc.trimMemory(); }
        if(step=='Refreshing RAM metrics...') await _load();
        if(mounted) setState(()=>progress=(progress+.18).clamp(0, .95));
      }
      await _load();
      if(!mounted)return;
      setState(() { busy=false; progress=1; operation='SMART OPTIMIZE completed'; });
      HapticFeedback.heavyImpact();
      await _saveHistory('SMART OPTIMIZE',1,1,0);
      _msg('Optimization scan completed • device metrics refreshed',green);
    } catch(e) {
      if(!mounted)return;
      setState(() { busy=false; progress=0; operation='SMART OPTIMIZE failed'; });
      _msg('Optimization failed: $e',red);
    }
  }

  Future<void> _quickScan() async {
    if(busy)return;
    await _scan('junk');
  }

  Future<void> _copyDeviceReport() async {
    final report = [
      'SADEE X DIMA DEVICE REPORT',
      '----------------------------',
      'Manufacturer : ${device['brand']??'--'}',
      'Model        : ${device['model']??'--'}',
      'Android      : ${device['androidVersion']??'--'}',
      'RAM          : ${device['usedRam']??'--'} / ${device['totalRam']??'--'}',
      'CPU          : ${metrics['cpuUsage']??'--'}%',
      'Battery      : ${metrics['batteryLevel']??'--'}%',
      'Temperature  : ${metrics['batteryTempC']??'--'} C',
      'Storage      : ${_bytes(metrics['storageUsed'])} / ${_bytes(metrics['storageTotal'])}',
      'Network      : ${metrics['networkType']??'--'}',
      'Health       : ${_health.toStringAsFixed(0)}%',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text:report));
    HapticFeedback.selectionClick();
    _msg('Device report copied',cyan);
  }

  void _openTab(int index) { HapticFeedback.selectionClick(); setState(()=>tab=index); }
  Future<void> _launchGame(bool max) async { if(busy)return; final pkg=max?'com.dts.freefiremax':'com.dts.freefireth'; if(!await svc.isGameInstalled(pkg)){_msg(max?'Free Fire MAX not installed':'Free Fire not installed',red);return;} setState(() { busy=true; operation='GAMING TURBO started...'; freeFireMax=max; }); await svc.trimMemory(); await Future.delayed(const Duration(milliseconds:250)); final ok=await svc.launchPackage(pkg); if(!mounted)return; setState(()=>busy=false);if(ok){_startGameTimer();_msg('GAMING TURBO activated • game launched',green);}else _msg('Game launch failed',red);}
  void _startGameTimer(){_gameTimer?.cancel();setState(() { gameRunning=true; gameSeconds=0; });_gameTimer=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState(()=>gameSeconds++);});}
  void _stopGame(){_gameTimer?.cancel();if(!mounted)return;final mins=gameSeconds~/60,secs=gameSeconds%60;setState(()=>gameRunning=false);_msg('Gaming session ${mins}m ${secs}s • Battery ${metrics['batteryLevel']??'--'}% • Temp ${metrics['batteryTempC']??'--'}°C',cyan);}
  double get _ramPercent=>double.tryParse((device['ramPercentage']??'0').replaceAll('%',''))??0;
  double get _health{final cpu=((metrics['cpuUsage']??0)as num).toDouble();final temp=((metrics['batteryTempC']??0)as num).toDouble();final thermal=(metrics['thermalName']??'NORMAL').toString();return (100-(_ramPercent*.45+cpu*.35+(temp>42?10:0)+(thermal=='SEVERE'||thermal=='CRITICAL'?15:0))).clamp(1,99);}
  String _bytes(dynamic v)=>svc.formatBytes(v is num?v:0);String _label(String c)=>{'downloads':'Download Folder','large':'Large Files','old':'Old / Unused','duplicates':'Duplicate Files','junk':'Temporary / Junk','empty':'Empty Folders'}[c]??c;String _time()=>gameRunning?'${gameSeconds~/60}m ${gameSeconds%60}s':'00m 00s';
  Future<bool> _confirm(String t,String m)=>showDialog<bool>(context:context,builder:(_)=>AlertDialog(backgroundColor:panel,title:Text(t,style:const TextStyle(color:Colors.white)),content:Text(m,style:const TextStyle(color:Colors.white70)),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('CANCEL')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('DELETE'))])) .then((v)=>v??false);
  void _msg(String s,Color c){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),backgroundColor:c,behavior:SnackBarBehavior.floating));}

  @override void dispose(){_metricsTimer?.cancel();_gameTimer?.cancel();_progressSub?.cancel();keyCtrl.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:panel,title:const Text('SADEE X DIMA OPTIMIZER',style:TextStyle(color:green,fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh,color:cyan))]),body:Stack(children:[IndexedStack(index:tab,children:[_home(),_performance(),_cleaner(),_gaming(),_device(),_history()]),if(busy)_overlay()]),bottomNavigationBar:NavigationBar(backgroundColor:panel,selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.home_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.speed_outlined),label:'Performance'),NavigationDestination(icon:Icon(Icons.cleaning_services_outlined),label:'Cleaner'),NavigationDestination(icon:Icon(Icons.sports_esports_outlined),label:'Gaming'),NavigationDestination(icon:Icon(Icons.phone_android),label:'Device'),NavigationDestination(icon:Icon(Icons.history),label:'History')]));
  Widget _home()=>_page([
    _heroCard(),
    _healthCard(),
    _metricsCard(),
    _quickActions(),
    _deviceCard(),
    _statusCard(),
  ]);

  Widget _heroCard()=>Container(
    margin:const EdgeInsets.only(bottom:12),
    padding:const EdgeInsets.all(18),
    decoration:BoxDecoration(
      gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF0D241B),Color(0xFF071014)]),
      borderRadius:BorderRadius.circular(24),
      border:Border.all(color:green.withOpacity(.65),width:1.4),
      boxShadow:[BoxShadow(color:green.withOpacity(.10),blurRadius:18,spreadRadius:1)],
    ),
    child:Row(children:[
      Container(width:72,height:72,decoration:BoxDecoration(shape:BoxShape.circle,color:Colors.black54,border:Border.all(color:green,width:2)),child:const Icon(Icons.bolt,color:green,size:42)),
      const SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('SADEE X DIMA',style:TextStyle(color:Colors.white,fontSize:23,fontWeight:FontWeight.w900,letterSpacing:1)),
        const SizedBox(height:3),
        const Text('REAL ANDROID MONITOR',style:TextStyle(color:green,fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1)),
        const SizedBox(height:9),
        Text(operation,style:const TextStyle(color:Colors.white54,fontSize:11)),
      ])),
    ]),
  );

  Widget _quickActions()=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('QUICK ACTIONS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)),
    const SizedBox(height:10),
    GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.75,children:[
      _quickButton('ONE-TAP OPTIMIZE',Icons.auto_awesome,purple,_oneTapOptimize),
      _quickButton('RAM BOOST',Icons.memory,cyan,_ramClean),
      _quickButton('QUICK CLEAN',Icons.cleaning_services,green,_quickScan),
      _quickButton('GAMING CENTER',Icons.sports_esports,red,()=>_openTab(3)),
      _quickButton('DEVICE INFO',Icons.phone_android,cyan,()=>_openTab(4)),
      _quickButton('COPY REPORT',Icons.copy,green,_copyDeviceReport),
    ])
  ]));

  Widget _quickButton(String t,IconData i,Color c,Future<void> Function() f)=>Material(
    color:Colors.black26,borderRadius:BorderRadius.circular(15),
    child:InkWell(onTap:busy?null:f,borderRadius:BorderRadius.circular(15),child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(borderRadius:BorderRadius.circular(15),border:Border.all(color:c.withOpacity(.35))),child:Row(children:[Icon(i,color:c,size:25),const SizedBox(width:9),Expanded(child:Text(t,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w900),maxLines:2))]))));

  Widget _statusCard()=>_card(Row(children:[
    Container(width:11,height:11,decoration:const BoxDecoration(color:green,shape:BoxShape.circle)),
    const SizedBox(width:10),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('LIVE MONITORING ACTIVE',style:TextStyle(color:green,fontWeight:FontWeight.w900)),Text('RAM • CPU • battery • thermal • storage',style:const TextStyle(color:Colors.white54,fontSize:11))])),
    IconButton(onPressed:_load,icon:const Icon(Icons.refresh,color:cyan)),
  ]));
  Widget _performance()=>_page([_title('PERFORMANCE CENTER','RAM • CPU • Battery • Storage • Thermal • Network',Icons.speed),_metricsCard(),_mode('PERFORMANCE MODE','App-owned cleanup + Android memory hint',Icons.bolt,purple,()=>_mode('PERFORMANCE')),_mode('BALANCED MODE','Monitoring-focused mode; no fake system changes.',Icons.balance,cyan,()=>_mode('BALANCED')),_mode('COOL DOWN','Temperature/thermal monitoring only.',Icons.ac_unit,green,()=>_mode('COOL')),_info('ANDROID LIMIT','Normal apps cannot silently force-free other apps RAM, alter CPU voltage/frequency, or clear other apps private data. This app reports real metrics and only performs permitted cleanup.')]);
  Widget _cleaner()=>_page([_title('ADVANCED CLEANER','Scan, select individual results, then delete',Icons.cleaning_services),_scanSummary(),_action('SCAN EVERYTHING',Icons.radar,cyan,_scanAll),const SizedBox(height:8),_action('DELETE SELECTED',Icons.delete_forever,red,_cleanSelected),const SizedBox(height:8),_cacheTile(),...categories.map(_categoryTile),_info('SCAN SAFETY','Heavy scans run in an Android background worker. Hashing is chunked and results are limited to keep memory use stable.')]);
  Widget _gaming()=>_page([_title('GAME LAUNCH CENTER','Safe pre-launch cleanup + live session monitor',Icons.sports_esports),_gameCard('FREE FIRE','com.dts.freefireth',false),_gameCard('FREE FIRE MAX','com.dts.freefiremax',true),_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('LIVE GAMING SESSION',style:TextStyle(color:cyan,fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(_time(),style:const TextStyle(color:green,fontSize:28,fontWeight:FontWeight.w900)),Text('Battery ${metrics['batteryLevel']??'--'}% • Temp ${metrics['batteryTempC']??'--'}°C • Thermal ${metrics['thermalName']??'--'}',style:const TextStyle(color:Colors.white70)),const SizedBox(height:8),Text('FPS/refresh: Android display refresh is ${metrics['refreshRateHz']??'--'} Hz when exposed by the device.',style:const TextStyle(color:Colors.white54,fontSize:12)),if(gameRunning)OutlinedButton(onPressed:_stopGame,child:const Text('STOP SESSION'))])),_info('GAME-SPECIFIC PRE-LAUNCH','The optimizer only performs app-owned cleanup/memory hints before launch. It does not inject or modify game files.')]);
  Widget _device()=>_page([_title('DEVICE CENTER','Live hardware and Android data',Icons.phone_android),_deviceCard(),_metricsCard(),_action('REFRESH DEVICE DATA',Icons.refresh,cyan,_load)]);
  Widget _history()=>_page([_title('OPERATION HISTORY','Before/after records from local operations',Icons.history),if(history.isEmpty)_info('NO HISTORY','Operations will appear here after scans and cleaning.') else ...history.map((h)=>_card(ListTile(contentPadding:EdgeInsets.zero,title:Text(h['operation']??'',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900)),subtitle:Text('${h['time']}\nScanned ${h['scanned']} • Cleaned ${h['cleaned']} • ${_bytes(h['bytes'])}',style:const TextStyle(color:Colors.white54,fontSize:11)),leading:const Icon(Icons.check_circle,color:green)) ))]);
  Widget _page(List<Widget> c)=>ListView(padding:const EdgeInsets.fromLTRB(14,14,14,28),children:c);
  Widget _title(String t,String s,IconData i)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Row(children:[Icon(i,color:cyan,size:30),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t,style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w900)),Text(s,style:const TextStyle(color:Colors.white54,fontSize:11))]))]));
  Widget _card(Widget c)=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.white10)),child:c);
  Widget _healthCard()=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Icon(Icons.favorite,color:green),const SizedBox(width:8),const Text('PERFORMANCE HEALTH SCORE',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900)),const Spacer(),Text('${_health.toStringAsFixed(0)}%',style:const TextStyle(color:green,fontSize:24,fontWeight:FontWeight.w900))]),const SizedBox(height:10),LinearProgressIndicator(value:_health/100,minHeight:8,borderRadius:BorderRadius.circular(8),color:green,backgroundColor:Colors.white10)]));
  Widget _metricsCard()=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('LIVE DEVICE METRICS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)),
    const SizedBox(height:10),
    GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:9,crossAxisSpacing:9,childAspectRatio:2.05,children:[
      _metric('RAM',device['ramPercentage']??'--',Icons.memory,cyan),
      _metric('CPU','${((metrics['cpuUsage']??0)as num).toStringAsFixed(0)}%',Icons.developer_board,purple),
      _metric('BATTERY','${metrics['batteryLevel']??'--'}%',Icons.battery_full,green),
      _metric('TEMP','${metrics['batteryTempC']??'--'}°C',Icons.thermostat,red),
      _metric('STORAGE','${_storagePercent()}%',Icons.storage,cyan),
      _metric('NETWORK',metrics['networkType']??'--',Icons.wifi,green),
      _metric('THERMAL',metrics['thermalName']??'--',Icons.whatshot,red),
      _metric('REFRESH','${metrics['refreshRateHz']??'--'} Hz',Icons.speed,purple),
    ])
  ]));
  String _storagePercent(){final u=(metrics['storageUsed']??0)as num,t=(metrics['storageTotal']??0)as num;return t<=0?'--':'${(u/t*100).round()}%';}String _uptime()=>_bytes(0).replaceAll('0 B','${metrics['uptimeHours']??'--'} h');
  Widget _metric(String t,String v,IconData i,Color c)=>Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.black38,borderRadius:BorderRadius.circular(15),border:Border.all(color:c.withOpacity(.25))),child:Row(children:[Container(width:40,height:40,decoration:BoxDecoration(color:c.withOpacity(.10),borderRadius:BorderRadius.circular(12)),child:Icon(i,color:c,size:23)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text(t,style:const TextStyle(color:Colors.white45,fontSize:9,fontWeight:FontWeight.w800)),const SizedBox(height:2),Text(v,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:c,fontWeight:FontWeight.w900,fontSize:16))]))]));
  Widget _deviceCard()=>_card(Column(children:[_row('Manufacturer',device['brand']??'--'),_row('Model',device['model']??'--'),_row('Android','${device['androidVersion']??'--'} • SDK ${device['sdkVersion']??'--'}'),_row('RAM','${device['usedRam']??'--'} / ${device['totalRam']??'--'}'),_row('Storage','${_bytes(metrics['storageUsed'])} / ${_bytes(metrics['storageTotal'])}'),_row('Battery','${metrics['batteryHealth']??'--'} • ${metrics['batteryLevel']??'--'}% • ${metrics['charging']==true?'Charging':'Not charging'}')]));
  Widget _row(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Text(a,style:const TextStyle(color:Colors.white45)),const Spacer(),Flexible(child:Text(b,textAlign:TextAlign.right,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)))]));
  Widget _action(String t,IconData i,Color c,Future<void> Function() f)=>SizedBox(height:52,child:ElevatedButton.icon(style:ElevatedButton.styleFrom(backgroundColor:c),onPressed:busy?null:f,icon:Icon(i,color:Colors.white),label:Text(t,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900))));
  Widget _mode(String t,String s,IconData i,Color c,Future<void> Function() f)=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(i,color:c),const SizedBox(width:8),Text(t,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900))]),const SizedBox(height:6),Text(s,style:const TextStyle(color:Colors.white54,fontSize:12)),const SizedBox(height:8),OutlinedButton(onPressed:busy?null:f,child:const Text('ACTIVATE'))]));
  Widget _cacheTile()=>_card(ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.cleaning_services,color:green),title:const Text('APP CACHE',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900)),subtitle:Text(_bytes(cacheBytes),style:const TextStyle(color:Colors.white54)),trailing:IconButton(onPressed:busy?null:_cleanCache,icon:const Icon(Icons.delete,color:red))));
  Widget _categoryTile(String c){final r=scans[c];final fs=List<Map<String,dynamic>>.from((r?['files']??[]).map((e)=>Map<String,dynamic>.from(e as Map)));return _card(Column(children:[Row(children:[Expanded(child:Text(_label(c),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900))),Text(r==null?'Not scanned':'${fs.length} • ${_bytes(r['totalBytes'])}',style:const TextStyle(color:Colors.white54,fontSize:11)),IconButton(onPressed:busy?null:()=>_scan(c),icon:const Icon(Icons.radar,color:cyan))]),if(fs.isNotEmpty)SizedBox(height:160,child:ListView.builder(itemCount:fs.length,itemBuilder:(_,i){final f=fs[i];final p=f['path'].toString();return CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,value:selectedPaths.contains(p),onChanged:(v)=>setState(()=>v==true?selectedPaths.add(p):selectedPaths.remove(p)),title:Text(f['name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white70,fontSize:12)),subtitle:Text(_bytes(f['size']),style:const TextStyle(color:Colors.white38,fontSize:10)),controlAffinity:ListTileControlAffinity.leading);})),if(fs.isNotEmpty)Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>setState(()=>selectedPaths.addAll(fs.map((e)=>e['path'].toString()))),child:const Text('SELECT ALL')))]));}
  Widget _scanSummary()=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Icon(Icons.radar,color:cyan),const SizedBox(width:8),Text(operation,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900)),const Spacer(),if(busy)TextButton(onPressed:_cancel,child:const Text('STOP'))]),const SizedBox(height:8),LinearProgressIndicator(value:busy?progress:null,color:green,backgroundColor:Colors.white10),const SizedBox(height:6),Text('${(progress*100).round()}% • selected ${selectedPaths.length}',style:const TextStyle(color:Colors.white54,fontSize:11))]));
  Widget _gameCard(String title, String pkg, bool max) {
    return _card(
      Column(
        children: [
          Row(
            children: [
              const Icon(Icons.sports_esports, color: green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                max ? 'MAX' : 'NORMAL',
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Text(
            pkg,
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: busy ? null : () => _launchGame(max),
              icon: const Icon(Icons.rocket_launch),
              label: const Text('GAMING TURBO + LAUNCH'),
            ),
          ),
        ],
      ),
    );
  }
  Widget _info(String t,String s)=>_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t,style:const TextStyle(color:cyan,fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(s,style:const TextStyle(color:Colors.white54,height:1.35,fontSize:12))]));
  Widget _overlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(.78),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: green.withOpacity(.45)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.memory, color: green, size: 44),
                const SizedBox(height: 10),
                Text(
                  operation,
                  style: const TextStyle(
                    color: green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 7,
                  child: LinearProgressIndicator(
                    value: progress,
                    color: cyan,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _cancel,
                  child: const Text('CANCEL / STOP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
