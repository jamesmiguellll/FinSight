import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:async';

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
  
  String _type = 'expense';
  String _category = 'Food';
  bool _isLoading = false;
  bool _isAiThinking = false;
  Timer? _debounce;

  final List<String> _categories = ['Food', 'Transport', 'Bills', 'Shopping', 'Others'];

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
    _debounce?.cancel();
    super.dispose();
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

  Future<void> _suggestCategory(String title) async {
    // Replace this with the user's Gemini API Key
    const apiKey = 'AIzaSyAvhyOB_-SmaaETUMN8_ioyrGE4sZ_wZUg'; 
    
    if (apiKey.isEmpty) {
      return; // Do nothing if key is not set
    }

    setState(() => _isAiThinking = true);
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      final prompt = 'Categorize the expense "$title" into exactly one of these categories: Food, Transport, Bills, Shopping, Others. Reply with just the category name and nothing else.';
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      final suggested = response.text?.trim() ?? '';
      if (_categories.contains(suggested)) {
        setState(() {
          _category = suggested;
        });
      }
    } catch (e) {
      debugPrint('AI Categorization error: $e');
    } finally {
      if (mounted) setState(() => _isAiThinking = false);
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data = {
        'user_id': userId,
        'title': _titleController.text.trim(),
        'amount': double.parse(_amountController.text.trim()),
        'category': _category,
        'type': _type,
      };

      if (widget.existingTransaction == null) {
        // Create
        await Supabase.instance.client.from('transactions').insert(data);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                decoration: const InputDecoration(
                  labelText: 'Title (e.g. Starbucks, Salary)',
                  border: OutlineInputBorder(),
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
                      child: DropdownButtonFormField<String>(
                        value: _category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _category = val);
                        },
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
