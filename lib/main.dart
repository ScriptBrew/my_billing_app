import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://zyqlvpdwnagrhtvavaah.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5cWx2cGR3bmFncmh0dmF2YWFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0NzgxNjgsImV4cCI6MjA4NjA1NDE2OH0.x2b4Yj06j3_kp969VCEd5pyeWPcTc03onE-jm8SgTUI',
  );
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: AuthScreen()));
}

// --- LOGIN SCREEN ---
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final MobileScannerController loginScanner = MobileScannerController();
  bool isLogin = true;

  Future<void> _handleAuth() async {
    try {
      final table = Supabase.instance.client.from('staff_login');
      if (isLogin) {
        final res = await table.select().eq('username', userCtrl.text).eq('password', passCtrl.text).maybeSingle();
        if (res != null) {
          await loginScanner.stop();
          _checkLocationAndNavigate(res['id']);
        } else {
          throw "Invalid Credentials";
        }
      } else {
        final res = await table.insert({'username': userCtrl.text, 'password': passCtrl.text}).select().single();
        await loginScanner.stop();
        _checkLocationAndNavigate(res['id']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _checkLocationAndNavigate(String userId) async {
    final res = await Supabase.instance.client.from('profiles').select().eq('id', userId).maybeSingle();
    if (res == null || res['location'] == null) {
      _showLocationSetup(userId);
    } else {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BillingHome(staffId: userId)));
    }
  }

  void _showLocationSetup(String userId) {
    final locCtrl = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text("First-Time Setup"),
      content: TextField(controller: locCtrl, decoration: const InputDecoration(labelText: "Enter Store Location")),
      actions: [ElevatedButton(onPressed: () async {
        await Supabase.instance.client.from('profiles').upsert({'id': userId, 'location': locCtrl.text});
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BillingHome(staffId: userId)));
      }, child: const Text("Save & Continue"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Center(
        child: Container(
          width: 400, padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("SUPERMARKET LOGIN", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Container(height: 120, width: double.infinity, color: Colors.black, child: MobileScanner(controller: loginScanner, onDetect: (cap) {
              final code = cap.barcodes.first.rawValue ?? "";
              if (code.contains(":")) {
                userCtrl.text = code.split(":")[0];
                passCtrl.text = code.split(":")[1];
                _handleAuth();
              }
            })),
            const SizedBox(height: 15),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Username", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _handleAuth, child: Text(isLogin ? "Login" : "Sign Up")),
            TextButton(onPressed: () => setState(() => isLogin = !isLogin), child: Text(isLogin ? "New user? Sign Up" : "Back to Login")),
          ]),
        ),
      ),
    );
  }
}

// --- BILLING HOME ---
class BillingHome extends StatefulWidget {
  final String staffId;
  const BillingHome({super.key, required this.staffId});
  @override
  State<BillingHome> createState() => _BillingHomeState();
}

class _BillingHomeState extends State<BillingHome> {
  List<Map<String, dynamic>> cart = [];
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final manualSearch = TextEditingController();
  final MobileScannerController mainController = MobileScannerController();
  Key scannerKey = UniqueKey();
  String? branchLocation;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  void _loadLocation() async {
    final res = await Supabase.instance.client.from('profiles').select().eq('id', widget.staffId).maybeSingle();
    setState(() => branchLocation = res?['location'] ?? "Main Counter");
  }

  Future<void> restartCam() async {
    await mainController.stop();
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) { setState(() { scannerKey = UniqueKey(); }); await mainController.start(); }
  }

  void _onDetect(String code) async {
    final res = await Supabase.instance.client.from('items').select().eq('barcode', code).maybeSingle();
    if (res != null) {
      setState(() {
        int i = cart.indexWhere((it) => it['barcode'] == code);
        if (i != -1) cart[i]['qty']++; else cart.add({...res, 'qty': 1});
      });
      manualSearch.clear();
    }
  }

  // --- ATTRACTIVE BILL DESIGN ---
  Future<void> _generateAndSaveBill(bool justGenerate) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text("SUPERMARKET INVOICE", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 15),
          pw.Text("Counter: $branchLocation"),
          pw.Text("Customer: ${nameCtrl.text}"),
          pw.Text("Mobile: ${phoneCtrl.text}"),
          pw.Text("Date: ${DateTime.now().toString().substring(0, 16)}"),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Item Description', 'Qty', 'Unit Price', 'Total (Rs.)'],
            data: cart.map((i) => [i['name'], i['qty'], "Rs. ${i['price']}", "Rs. ${i['price'] * i['qty']}"]).toList(),
          ),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text("GRAND TOTAL: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty'])).toStringAsFixed(2)}", 
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 50),
          pw.Center(child: pw.Text("THANK YOU FOR SHOPPING WITH US!", style: pw.TextStyle(fontSize: 14, fontStyle: pw.FontStyle.italic))),
        ]),
      ),
    ));
    
    if (justGenerate) {
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } else {
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'Invoice_${nameCtrl.text}.pdf');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Billing Dashboard"), actions: [
        ElevatedButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.add), label: const Text("ADD NEW ITEM")),
        IconButton(onPressed: () => setState(() => cart.clear()), icon: const Icon(Icons.delete_sweep, color: Colors.red)),
      ]),
      body: Row(children: [
        SizedBox(width: 380, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Container(height: 220, decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent)), 
            child: MobileScanner(key: scannerKey, controller: mainController, onDetect: (cap) => _onDetect(cap.barcodes.first.rawValue!))),
          const SizedBox(height: 20),
          TextField(controller: manualSearch, decoration: const InputDecoration(labelText: "Barcode Search", border: OutlineInputBorder()), onSubmitted: _onDetect),
          const SizedBox(height: 10),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Customer Name", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Mobile Number", border: OutlineInputBorder())),
        ]))),
        const VerticalDivider(),
        Expanded(child: Column(children: [
          Expanded(child: ListView.builder(itemCount: cart.length, itemBuilder: (ctx, i) => ListTile(
            title: Text(cart[i]['name']), subtitle: Text("Rs. ${cart[i]['price']} x ${cart[i]['qty']}"),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () => setState(() => cart[i]['qty'] > 1 ? cart[i]['qty']-- : cart.removeAt(i))),
              Text("${cart[i]['qty']}"),
              IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => cart[i]['qty']++)),
            ]),
          ))),
          Container(padding: const EdgeInsets.all(25), color: Colors.blueGrey[50], child: Column(children: [
            Text("TOTAL: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty'])).toStringAsFixed(2)}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton(onPressed: () => _generateAndSaveBill(false), child: const Text("SAVE BILL")),
              ElevatedButton(onPressed: () => _generateAndSaveBill(true), child: const Text("GENERATE BILL")),
            ])
          ]))
        ]))
      ]),
    );
  }

  void _showAddDialog() async {
    await mainController.stop(); // Stops main scanner to avoid camera conflict
    final b = TextEditingController(); final n = TextEditingController(); final p = TextEditingController();
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text("Register Product"),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 150, child: MobileScanner(onDetect: (c) => b.text = c.barcodes.first.rawValue ?? "")),
        TextField(controller: b, decoration: const InputDecoration(labelText: "Barcode")),
        TextField(controller: n, decoration: const InputDecoration(labelText: "Item Name")),
        TextField(controller: p, decoration: const InputDecoration(labelText: "Price (Rs.)")),
      ])),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); restartCam(); }, child: const Text("Cancel")),
        ElevatedButton(onPressed: () async {
          await Supabase.instance.client.from('items').insert({'barcode': b.text, 'name': n.text, 'price': double.tryParse(p.text) ?? 0.0});
          Navigator.pop(ctx); restartCam(); 
        }, child: const Text("Save")),
      ],
    ));
  }
}