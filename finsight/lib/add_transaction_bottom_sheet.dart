import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'finance_service.dart';

class AddTransactionBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? existingTransaction;
  final VoidCallback onSaved;

  const AddTransactionBottomSheet({
    super.key,
    this.existingTransaction,
    required this.onSaved,
  });

  @override
  State<AddTransactionBottomSheet> createState() => _AddTransactionBottomSheetState();
}

class _AddTransactionBottomSheetState extends State<AddTransactionBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController(text: 'Food');

  String _type = 'expense';
  String _category = 'Food';
  bool _isLoading = false;
  bool _isAiThinking = false;
  bool _isScanning = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();
  Timer? _debounce;

  List<String> _categories = ['Food', 'Transport', 'Bills', 'Shopping', 'Others'];

  @override
  void initState() {
    super.initState();
    if (widget.existingTransaction != null) {
      _titleController.text = widget.existingTransaction!['title'];
      _amountController.text = widget.existingTransaction!['amount'].toString();
      _type = widget.existingTransaction!['type'];
      _category = widget.existingTransaction!['category'];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- RECEIPT SCANNER ---
  Future<void> _scanReceipt(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() => _isScanning = true);
      
      final result = await FinanceService.scanReceipt(File(image.path));
      
      if (result != null && mounted) {
        setState(() {
          if (result['merchant'] != null) _titleController.text = result['merchant'];
          if (result['amount'] != null) _amountController.text = result['amount'].toString();
          if (result['category'] != null) {
            final cat = result['category'].toString();
            if (!_categories.contains(cat)) {
              _categories.add(cat);
            }
            _category = cat;
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to read receipt')));
      }
    } catch (e) {
      debugPrint('Error scanning receipt: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  _scanReceipt(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _scanReceipt(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  // --- GEMINI AI AUTO-CATEGORIZATION ---
  void _onTitleChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () {
      if (query.trim().isNotEmpty && _type == 'expense') {
        _suggestCategory(query);
      }
    });
  }

  // Local rule-based categorizer — instant, no API quota needed
  String? _localCategorize(String input) {
    final s = input.toLowerCase().trim();

    // --- FOOD ---
    const food = [
      'jollibee', 'mcdo', "mcdonald", 'kfc', 'chowking', 'mang inasal',
      'greenwich', 'yellow cab', 'pizza hut', 'domino', 'starbucks',
      'coffee bean', 'dunkin', 'krispy kreme', 'red ribbon', 'goldilocks',
      "max's", 'pancake house', 'shakeys', 'army navy', 'burger king',
      'zark', 'tropical hut', 'bonchon', 'potato corner', 'sbarro',
      'jamba juice', 'happy lemon', 'cbtl', 'gerry', 'aristocrat',
      '7-eleven', '7eleven', 'ministop', 'family mart', 'lawson',
      'grabfood', 'foodpanda', 'pick a roo', 'lalafood',
      'paluto', 'carenderia', 'lutong', 'restaurant', 'eatery',
      'milk tea', 'taho', 'balut', 'siomai', 'siopao',
      'rice', 'bread', 'milk', 'groceries', 'grocery', 'supermarket',
      'puregold', 'sm supermarket', 'robinsons supermarket', 'walter mart',
      'savemore', 'cherry', 'csi', 'landers', 'costco',
      'food', 'snack', 'meal', 'lunch', 'dinner', 'breakfast', 'cafe',
    ];

    // --- TRANSPORT ---
    const transport = [
      'angkas', 'joyride', 'grab car', 'grab bike', 'grab express',
      'grab', 'lalamove', 'mrspeedy', 'maxim', 'indrive',
      'mrt', 'lrt', 'pnr', 'beep', 'rail', 'bus', 'jeep', 'jeepney',
      'taxi', 'ltfrb', 'uv express', 'fx', 'van', 'tricycle',
      'fuel', 'petron', 'shell', 'caltex', 'seaoil', 'phoenix gas',
      'gasoline', 'diesel', 'gas station', 'toll', 'expressway',
      'nlex', 'slex', 'tplex', 'cavitex', 'mctep',
      'parking', 'transport', 'commute', 'fare', 'j&t', 'jnt', 'lbc',
    ];

    // --- BILLS ---
    const bills = [
      'meralco', 'maynilad', 'manila water', 'mwss',
      'pldt', 'globe', 'smart', 'dito', 'converge', 'sky broadband',
      'sky cable', 'cignal', 'abs-cbn', 'netflix', 'spotify',
      'youtube premium', 'apple music', 'disney', 'viu', 'iflix',
      'philhealth', 'sss', 'pagibig', 'pag-ibig', 'bir', 'tax',
      'rent', 'condo', 'hoa', 'association dues', 'water bill',
      'electric', 'electricity', 'internet', 'wifi', 'load', 'prepaid',
      'postpaid', 'subscription', 'insurance', 'premium',
    ];

    // --- SHOPPING ---
    const shopping = [
      'shopee', 'lazada', 'zalora', 'shein', 'temu', 'amazon',
      'sm store', 'sm department', 'robinsons dept', 'rustan',
      'landmark', 'true value', 'ace hardware', 'handyman',
      'h&m', 'uniqlo', 'zara', 'nike', 'adidas', 'new balance',
      'converse', 'vans', 'penshoppe', 'bench', 'oxygen', 'folded',
      'surplus', 'secondhand', 'ukay', 'divisoria', 'tiangge',
      'national bookstore', 'powerbooks', 'fully booked',
      'gadget', 'phone', 'laptop', 'computer', 'iphone', 'samsung',
      'dyson', 'abenson', 'anson', 'octagon', 'i-store', 'beyond',
      'watsons', 'mercury drug', 'rose pharmacy', 'southstar',
      'clothing', 'shoes', 'bag', 'shirt', 'pants', 'dress',
    ];

    // --- ENTERTAINMENT ---
    const entertainment = [
      'sm cinema', 'ayala cinemas', 'robinsons movieworld', 'golden screen',
      'netflix', 'spotify', 'steam', 'playstation', 'xbox', 'nintendo',
      'resorts world', 'okada', 'solaire', 'city of dreams', 'casino',
      'bgc', 'eastwood', 'mall of asia', 'starwalk', 'lipa cinema',
      'bowling', 'billiards', 'karaoke', 'videoke', 'arcade',
      'gym', 'fitness', 'anytime fitness', 'gold\'s gym', 'snap fitness',
      'spa', 'massage', 'salon', 'nail', 'barbershop',
      'entertainment', 'movie', 'concert', 'event', 'ticket',
    ];

    // --- HEALTHCARE ---
    const healthcare = [
      'hospital', 'clinic', 'doctor', 'dentist', 'dental',
      'optometrist', 'eye', 'laboratory', 'lab', 'medical',
      'pharmacy', 'medicine', 'vitamins', 'supplements',
      'st. luke', 'makati med', 'medical city', 'unilab',
      'watsons', 'mercury drug', 'rose pharmacy', 'generika',
      'pcso', 'checkup', 'consultation', 'therapy',
    ];

    // --- EDUCATION ---
    const education = [
      'tuition', 'school', 'university', 'college', 'institute',
      'books', 'notebook', 'school supplies', 'national bookstore',
      'tutorial', 'review center', 'ielts', 'toefl', 'tesda',
      'coursera', 'udemy', 'skillshare', 'pluralsight',
    ];

    for (final kw in food) { if (s.contains(kw)) return 'Food'; }
    for (final kw in transport) { if (s.contains(kw)) return 'Transport'; }
    for (final kw in bills) { if (s.contains(kw)) return 'Bills'; }
    for (final kw in shopping) { if (s.contains(kw)) return 'Shopping'; }
    for (final kw in entertainment) { if (s.contains(kw)) return 'Entertainment'; }
    for (final kw in healthcare) { if (s.contains(kw)) return 'Healthcare'; }
    for (final kw in education) { if (s.contains(kw)) return 'Education'; }

    return null; // unknown — will try Gemini
  }

  Future<void> _suggestCategory(String title) async {
    if (_type == 'income') {
      if (mounted) {
        setState(() {
          if (!_categories.contains('Income')) _categories.add('Income');
          _category = 'Income';
          _categoryController.text = 'Income';
        });
      }
      return;
    }

    setState(() => _isAiThinking = true);
    try {
      // Step 1: Try fast local categorizer first (no API calls needed)
      final localResult = _localCategorize(title);
      if (localResult != null && mounted) {
        setState(() {
          if (!_categories.contains(localResult)) _categories.add(localResult);
          _category = localResult;
          _categoryController.text = localResult;
        });
        return; // done — no API needed
      }

      // Step 2: Fallback to FastAPI backend for unknown inputs
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        debugPrint('Cannot suggest category: user session is null');
        return;
      }

      final url = Uri.parse('http://192.168.254.118:8000/predict-category');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({
          'merchant_name': title,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final suggested = (data['category'] as String?)?.trim();
        if (suggested != null && suggested.isNotEmpty && mounted) {
          setState(() {
            if (!_categories.contains(suggested)) _categories.add(suggested);
            _category = suggested;
            _categoryController.text = suggested;
          });
        }
      } else {
        debugPrint('Backend category prediction error: ${response.statusCode}');
        // If API fails too, set a sensible default
        if (mounted) {
          setState(() {
            _category = 'Shopping';
            _categoryController.text = 'Shopping';
          });
        }
      }
    } catch (e) {
      debugPrint('AI Categorization error: $e');
    } finally {
      if (mounted) setState(() => _isAiThinking = false);
    }
  }


  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final amount = double.parse(_amountController.text.trim());
      
      // Check for sufficient balance if it's an expense
      if (_type == 'expense') {
        final userId = Supabase.instance.client.auth.currentUser!.id;
        final transactions = await Supabase.instance.client
            .from('transactions')
            .select()
            .eq('user_id', userId);
        double totalIncome = 0;
        double totalExpense = 0;
        for (var t in transactions) {
          final type = t['type'] as String;
          final amt = (t['amount'] as num).toDouble();
          if (type == 'income') totalIncome += amt;
          if (type == 'expense') totalExpense += amt;
        }
        double balance = totalIncome - totalExpense;
        
        // If editing an existing expense, we add its old amount back to the balance
        // so we are calculating the balance *before* this specific transaction occurred.
        if (widget.existingTransaction != null && widget.existingTransaction!['type'] == 'expense') {
          final oldAmt = (widget.existingTransaction!['amount'] as num).toDouble();
          balance += oldAmt;
        }

        if (amount > balance) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Insufficient balance! You do not have enough funds.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data = {
        'user_id': userId,
        'title': _titleController.text.trim(),
        'amount': double.parse(_amountController.text.trim()),
        'category': _category,
        'type': _type,
      };

      if (widget.existingTransaction == null) {
        final success = await FinanceService.addTransaction(data);
        if (!success) throw Exception('Failed to add transaction via backend');
      } else {
        // Update
        await Supabase.instance.client
            .from('transactions')
            .update(data)
            .eq('id', widget.existingTransaction!['id']);
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.existingTransaction == null ? 'New Transaction' : 'Edit Transaction',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 16),

              // Scan Receipt Button
              if (_isScanning)
                const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('📱 Processing on-device...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ))
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Scan Receipt (On-Device OCR)'),
                    onPressed: () => _showImageSourceActionSheet(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF634DFF),
                      side: const BorderSide(color: Color(0xFF634DFF)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              // Type Segmented Control
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _type = 'expense'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'expense' ? Colors.red.withOpacity(0.1) : Colors.transparent,
                          border: Border.all(color: _type == 'expense' ? Colors.red : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text('Expense', style: TextStyle(color: _type == 'expense' ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _type = 'income'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'income' ? Colors.green.withOpacity(0.1) : Colors.transparent,
                          border: Border.all(color: _type == 'income' ? Colors.green : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text('Income', style: TextStyle(color: _type == 'income' ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Title
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _type == 'expense' ? 'Title (e.g. Starbucks, Meralco)' : 'Title (e.g. Salary, Allowance)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onTitleChanged,
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₱)',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (double.tryParse(val) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category Dropdown
              if (_type == 'expense') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _categoryController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Category (AI Auto-Categorized)',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          prefixIcon: const Icon(Icons.auto_awesome, color: Color(0xFF634DFF)),
                        ),
                      ),
                    ),
                    if (_isAiThinking)
                      const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: SizedBox(
                          width: 20, height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2)
                        ),
                      )
                  ],
                ),
                if (_isAiThinking)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('✨ AI is suggesting a category...', style: TextStyle(color: Colors.purple, fontSize: 12)),
                  ),
                const SizedBox(height: 24),
              ],

              // Error Message
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF634DFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : Text(widget.existingTransaction == null ? 'Save Transaction' : 'Update Transaction', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
