import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize sqflite for desktop (Windows/Linux/Mac)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Spreadsheet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SpreadsheetPage(),
    );
  }
}

class RowData {
  int? id;
  String currency;
  String amount;
  String rate;
  String prixBi;
  String outCom;
  String people;
  String reference;
  String responsible;
  bool checking;
  String notes;
  String date;
  String profits;
  bool locked;

  RowData({
    this.id,
    this.currency = 'DZD-V',
    this.amount = '',
    this.rate = '',
    this.prixBi = '',
    this.outCom = 'COM',
    this.people = '',
    this.reference = '',
    this.responsible = '',
    this.checking = false,
    this.notes = '',
    this.date = '',
    this.profits = '0',
  this.locked = false,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'currency': currency,
      'amount': amount,
      'rate': rate,
      'prixBi': prixBi,
      'outCom': outCom,
      'people': people,
      'reference': reference,
      'responsible': responsible,
      'checking': checking ? 1 : 0,
      'notes': notes,
      'date': date,
      'profits': profits,
  'locked': locked ? 1 : 0,
    };
  }

  static RowData fromMap(Map<String, Object?> m) {
    return RowData(
      id: m['id'] as int?,
      currency: m['currency'] as String? ?? 'DZD-V',
      amount: m['amount'] as String? ?? '',
      rate: m['rate'] as String? ?? '',
      prixBi: m['prixBi'] as String? ?? '',
      outCom: m['outCom'] as String? ?? 'COM',
      people: m['people'] as String? ?? '',
      reference: m['reference'] as String? ?? '',
      responsible: m['responsible'] as String? ?? '',
      checking: (m['checking'] as int? ?? 0) == 1,
      notes: m['notes'] as String? ?? '',
      date: m['date'] as String? ?? '',
      profits: m['profits'] as String? ?? '0',
  locked: (m['locked'] as int? ?? 0) == 1,
    );
  }
}

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  static Future<Database> initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'spreadsheet.db');
      return await openDatabase(path, version: 1, onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE rows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            currency TEXT,
            amount TEXT,
            rate TEXT,
            prixBi TEXT,
            outCom TEXT,
            people TEXT,
            reference TEXT,
            responsible TEXT,
            checking INTEGER,
            notes TEXT,
            date TEXT,
            profits TEXT,
            locked INTEGER DEFAULT 0
          )
        ''');
        // table to hold dropdown option values so users can add new ones
        await db.execute('''
          CREATE TABLE options (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            value TEXT
          )
        ''');
        // insert some defaults
        final defaults = {
          'currency': ['DZD-V', 'USD', 'EUR'],
          'people': ['SAMED', 'AHMED', 'LINA'],
          'reference': ['BARIDI', 'REF1', 'REF2'],
          'responsible': ['SAMED', 'MOHAMED', 'LINA'],
        };
        for (final entry in defaults.entries) {
          for (final v in entry.value) {
            await db.insert('options', {'type': entry.key, 'value': v});
          }
        }
    });
  }

  static Future<List<String>> getOptions(String type) async {
    final database = await DBHelper.db;
    final res = await database.query('options', where: 'type = ?', whereArgs: [type], orderBy: 'id');
  final list = res.map((m) => (m['value'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  return LinkedHashSet<String>.from(list).toList();
  }

  static Future<int> addOption(String type, String value) async {
    final database = await DBHelper.db;
    // avoid duplicates
    final existing = await database.query('options', where: 'type = ? AND value = ?', whereArgs: [type, value]);
    if (existing.isNotEmpty) return existing.first['id'] as int? ?? 0;
    return await database.insert('options', {'type': type, 'value': value});
  }

  static Future<int> deleteOption(String type, String value) async {
    final database = await DBHelper.db;
    return await database.delete('options', where: 'type = ? AND value = ?', whereArgs: [type, value]);
  }

  static Future<int> insertRow(RowData r) async {
    final database = await db;
    return await database.insert('rows', r.toMap());
  }

  static Future<int> updateRow(RowData r) async {
    final database = await db;
    return await database.update('rows', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  static Future<int> deleteRow(int id) async {
    final database = await db;
    return await database.delete('rows', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<RowData>> getAllRows() async {
    final database = await db;
    final res = await database.query('rows', orderBy: 'id');
    return res.map((m) {
      final map = Map<String, Object?>.from(m);
      if (!map.containsKey('locked')) map['locked'] = 0;
      return RowData.fromMap(map);
    }).toList();
  }
}

class SpreadsheetPage extends StatefulWidget {
  const SpreadsheetPage({super.key});

  @override
  State<SpreadsheetPage> createState() => _SpreadsheetPageState();
}

class _SpreadsheetPageState extends State<SpreadsheetPage> {
  List<RowData> rows = [];
  final Map<int, Timer> _debounceTimers = {};

  final List<String> currencies = ['DZD-V', 'USD', 'EUR'];
  final List<String> outComOptions = ['COM', 'OUT'];
  final List<String> peopleOptions = ['SAMED', 'AHMED', 'LINA'];
  final List<String> referenceOptions = ['BARIDI', 'REF1', 'REF2'];
  final List<String> responsibleOptions = ['SAMED', 'MOHAMED', 'LINA'];

  @override
  void initState() {
    super.initState();
    _loadRows();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final cur = await DBHelper.getOptions('currency');
    final ppl = await DBHelper.getOptions('people');
    final refs = await DBHelper.getOptions('reference');
    final resp = await DBHelper.getOptions('responsible');
    setState(() {
      if (cur.isNotEmpty) {
        currencies
        ..clear()
        ..addAll(cur);
      }
      if (ppl.isNotEmpty) {
        peopleOptions
        ..clear()
        ..addAll(ppl);
      }
      if (refs.isNotEmpty) {
        referenceOptions
        ..clear()
        ..addAll(refs);
      }
      if (resp.isNotEmpty) {
        responsibleOptions
        ..clear()
        ..addAll(resp);
      }
      // ensure people and responsible lists are the same (union)
      final merged = LinkedHashSet<String>.from([...peopleOptions, ...responsibleOptions]).toList();
      peopleOptions
        ..clear()
        ..addAll(merged);
      responsibleOptions
        ..clear()
        ..addAll(merged);
    });
  }

  Future<void> _loadRows() async {
    final loaded = await DBHelper.getAllRows();
    setState(() {
      rows = loaded;
    });
  }

  Future<void> _addRow() async {
    final now = DateTime.now();
    final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final newRow = RowData(date: dateStr);
    final id = await DBHelper.insertRow(newRow);
    newRow.id = id;
    setState(() {
      rows.add(newRow);
    });
  }

  Future<void> _saveRow(RowData r) async {
    if (r.id == null) {
      final id = await DBHelper.insertRow(r);
      r.id = id;
    } else {
      await DBHelper.updateRow(r);
    }
  }

  void _scheduleSave(RowData r) {
    if (r.id == null) return;
    final id = r.id!;
    _debounceTimers[id]?.cancel();
    _debounceTimers[id] = Timer(const Duration(seconds: 1), () async {
      await _saveRow(r);
    });
  }

  Future<void> _removeRow(RowData r) async {
    if (r.id != null) {
      await DBHelper.deleteRow(r.id!);
    }
    setState(() {
      rows.remove(r);
    });
  }

  Widget _buildRowCard(RowData r) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Currency
              SizedBox(
                width: 160,
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: r.currency,
                        items: LinkedHashSet<String>.from([r.currency, ...currencies]).toList().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: r.locked
                          ? null
                          : (v) {
                              setState(() => r.currency = v ?? r.currency);
                              _scheduleSave(r);
                            },
                      decoration: const InputDecoration(labelText: 'CURNSY'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final txt = await showDialog<String>(context: context, builder: (ctx) {
                        final ctrl = TextEditingController();
                        return AlertDialog(
                          title: const Text('Add currency'),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add'))],
                        );
                      });
                      if (txt != null && txt.isNotEmpty) {
                        await DBHelper.addOption('currency', txt);
                        _loadOptions();
                        setState(() => r.currency = txt);
                        _scheduleSave(r);
                      }
                    },
                  )
                  ,
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove currency',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(context: context, builder: (ctx) {
                        return AlertDialog(
                          title: const Text('Remove currency'),
                          content: Text('Remove "${r.currency}" from currency list? This will not change existing rows.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))],
                        );
                      });
                      if (confirm == true) {
                        await DBHelper.deleteOption('currency', r.currency);
                        await _loadOptions();
                        setState(() {
                          // if current value was removed, set to first available
                          if (!currencies.contains(r.currency)) {
                            r.currency = currencies.isNotEmpty ? currencies.first : '';
                          }
                        });
                        _scheduleSave(r);
                      }
                    },
                  ),
                ]),
              ),
              const SizedBox(width: 12),

              // Amount
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: r.amount,
                  decoration: const InputDecoration(labelText: '+/− AMOUNT'),
                  keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
                  onChanged: r.locked
                      ? null
                      : (v) {
                          setState(() {
                            r.amount = v;
                            // recalc prixBi (allow negative numbers)
                            final a = double.tryParse(r.amount.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0.0;
                            final rate = double.tryParse(r.rate.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0.0;
                            r.prixBi = (a * rate).toStringAsFixed(2);
                            // set outCom based on sign of amount: positive -> COM, negative -> OUT
                            r.outCom = a >= 0 ? 'COM' : 'OUT';
                          });
                          _scheduleSave(r);
                        },
                  onFieldSubmitted: (_) => _saveRow(r),
                ),
              ),
              const SizedBox(width: 12),

              // Rate
              SizedBox(
                width: 140,
                child: TextFormField(
                  initialValue: r.rate,
                  decoration: const InputDecoration(labelText: 'RATE'),
                  keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
                  onChanged: r.locked
                      ? null
                      : (v) {
                          setState(() {
                            r.rate = v;
                            final a = double.tryParse(r.amount.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0.0;
                            final rate = double.tryParse(r.rate.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0.0;
                            r.prixBi = (a * rate).toStringAsFixed(2);
                          });
                          _scheduleSave(r);
                        },
                  onFieldSubmitted: (_) => _saveRow(r),
                ),
              ),
              const SizedBox(width: 12),

              // PRIX BI (computed = amount * rate) - show instantly
              SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PRIX BI', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text(r.prixBi.isEmpty ? '0.00' : r.prixBi,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // OUT/COM (read-only, set automatically from Amount sign)
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OUT/COM', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text(r.outCom, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // PEOPLE
              SizedBox(
                width: 160,
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: r.people.isEmpty ? peopleOptions.first : r.people,
                        items: LinkedHashSet<String>.from([r.people, ...peopleOptions]).toList().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: r.locked
                          ? null
                          : (v) {
                              setState(() => r.people = v ?? r.people);
                              _scheduleSave(r);
                            },
                      decoration: const InputDecoration(labelText: 'PEOPLE'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final txt = await showDialog<String>(context: context, builder: (ctx) {
                        final ctrl = TextEditingController();
                        return AlertDialog(
                          title: const Text('Add person'),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add'))],
                        );
                      });
                      if (txt != null && txt.isNotEmpty) {
                        await DBHelper.addOption('people', txt);
                        _loadOptions();
                        setState(() => r.people = txt);
                        _scheduleSave(r);
                      }
                    },
                  )
                ]),
              ),
              const SizedBox(width: 12),

              // REFERENCE (dropdown)
              SizedBox(
                width: 160,
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: r.reference.isEmpty ? null : r.reference,
                        items: LinkedHashSet<String>.from([if (r.reference.isNotEmpty) r.reference, ...referenceOptions]).toList().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: r.locked
                          ? null
                          : (v) {
                              setState(() => r.reference = v ?? r.reference);
                              _scheduleSave(r);
                            },
                      decoration: const InputDecoration(labelText: 'REFERENCE'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final txt = await showDialog<String>(context: context, builder: (ctx) {
                        final ctrl = TextEditingController();
                        return AlertDialog(
                          title: const Text('Add reference'),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add'))],
                        );
                      });
                      if (txt != null && txt.isNotEmpty) {
                        await DBHelper.addOption('reference', txt);
                        _loadOptions();
                        setState(() => r.reference = txt);
                        _scheduleSave(r);
                      }
                    },
                  )
                ]),
              ),
              const SizedBox(width: 12),

              // RESPONSABLE (dropdown)
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: r.responsible.isEmpty ? null : r.responsible,
                    items: LinkedHashSet<String>.from([if (r.responsible.isNotEmpty) r.responsible, ...responsibleOptions]).toList().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: r.locked
                      ? null
                      : (v) {
                          setState(() => r.responsible = v ?? r.responsible);
                          _scheduleSave(r);
                        },
                  decoration: const InputDecoration(labelText: 'RESPONSABLE'),
                ),
              ),
              const SizedBox(width: 12),

              // CHECKING
              Column(
                children: [
                  const Text('CHECKING'),
                  Checkbox(
                    value: r.checking,
                    onChanged: r.locked
                        ? null
                        : (v) {
                            setState(() => r.checking = v ?? false);
                            _scheduleSave(r);
                          },
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // NOTES
              SizedBox(
                width: 200,
                child: TextFormField(
                  initialValue: r.notes,
                  decoration: const InputDecoration(labelText: 'NOTES'),
                  onChanged: r.locked ? null : (v) => r.notes = v,
                  onFieldSubmitted: r.locked ? null : (_) => _scheduleSave(r),
                ),
              
              ),
              const SizedBox(width: 12),

              // DATE
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: r.date,
                  decoration: const InputDecoration(labelText: 'DATE'),
                  onChanged: r.locked ? null : (v) => r.date = v,
                  onFieldSubmitted: r.locked ? null : (_) => _scheduleSave(r),
                ),
              ),
              const SizedBox(width: 12),

              // PROFITS
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: r.profits,
                  decoration: const InputDecoration(labelText: 'PROFITS'),
                  onChanged: r.locked ? null : (v) => r.profits = v,
                  onFieldSubmitted: r.locked ? null : (_) => _scheduleSave(r),
                ),
              ),
              const SizedBox(width: 12),

              // Save button
              ElevatedButton.icon(
                onPressed: r.locked
                    ? null
                    : () async {
                        await _saveRow(r);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                      },
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _removeRow(r),
                icon: const Icon(Icons.delete),
                label: const Text('Remove'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول البيانات'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: rows.length,
              itemBuilder: (context, index) => _buildRowCard(rows[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Row'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
