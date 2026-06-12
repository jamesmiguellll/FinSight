import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'add_transaction_bottom_sheet.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching transactions: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTransaction(String id) async {
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id);
      _fetchTransactions();
    } catch (e) {
      debugPrint("Error deleting transaction: $e");
    }
  }

  void _showAddTransactionModal({Map<String, dynamic>? transaction}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => AddTransactionBottomSheet(
        existingTransaction: transaction,
        onSaved: () {
          setState(() => _isLoading = true);
          _fetchTransactions();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions'),
        backgroundColor: const Color(0xFF634DFF),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? const Center(child: Text("No transactions yet."))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _transactions.length,
                  itemBuilder: (context, index) {
                    final t = _transactions[index];
                    final isIncome = t['type'] == 'income';
                    final amount = (t['amount'] as num).toDouble();
                    final date = DateTime.parse(t['created_at']).toLocal();
                    final dateFormatted = DateFormat('MMM d, yyyy h:mm a').format(date);

                    IconData icon;
                    Color bg;
                    Color iconColor;
                    switch (t['category']) {
                      case 'Food':
                        icon = Icons.restaurant;
                        bg = const Color(0xFFE1BEE7);
                        iconColor = Colors.purple;
                        break;
                      case 'Transport':
                        icon = Icons.directions_car;
                        bg = const Color(0xFFB2EBF2);
                        iconColor = Colors.cyan;
                        break;
                      case 'Bills':
                        icon = Icons.receipt;
                        bg = const Color(0xFFFFE082);
                        iconColor = Colors.orange;
                        break;
                      case 'Shopping':
                        icon = Icons.shopping_bag;
                        bg = const Color(0xFFBBDEFB);
                        iconColor = Colors.blue;
                        break;
                      default:
                        icon = isIncome ? Icons.account_balance_wallet : Icons.category;
                        bg = isIncome ? const Color(0xFFC8E6C9) : const Color(0xFFF5F5F5);
                        iconColor = isIncome ? Colors.green : Colors.grey;
                    }

                    return Dismissible(
                      key: Key(t['id'].toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteTransaction(t['id'].toString()),
                      child: InkWell(
                        onTap: () => _showAddTransactionModal(transaction: t),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: bg.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                                child: Icon(icon, color: iconColor),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(dateFormatted, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isIncome ? '+${_currencyFormat.format(amount)}' : _currencyFormat.format(amount),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.green : Colors.black),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(t['category'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
