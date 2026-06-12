import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'finance_service.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  List<Map<String, dynamic>> _goals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGoals();
  }

  Future<void> _fetchGoals() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('savings_goals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _goals = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching goals: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGoal(String id) async {
    try {
      await Supabase.instance.client.from('savings_goals').delete().eq('id', id);
      _fetchGoals();
    } catch (e) {
      debugPrint("Error deleting goal: $e");
    }
  }

  void _showAddGoalModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _AddGoalBottomSheet(onSaved: () {
        setState(() => _isLoading = true);
        _fetchGoals();
      }),
    );
  }

  Future<void> _addFundsToGoal(String id, double currentAmount, String goalName) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final txData = await Supabase.instance.client.from('transactions').select().eq('user_id', userId);
    double totalIncome = 0;
    double totalExpense = 0;
    for (var t in txData) {
      if (t['type'] == 'income') totalIncome += (t['amount'] as num).toDouble();
      if (t['type'] == 'expense') totalExpense += (t['amount'] as num).toDouble();
    }
    double totalBalance = totalIncome - totalExpense;

    TextEditingController amountController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deposit Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available Balance: ₱${totalBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(amountController.text.trim());
              if (val != null && val > 0) {
                if (val > totalBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insufficient balance!')));
                  return;
                }
                Navigator.pop(context);
                try {
                  await Supabase.instance.client
                      .from('savings_goals')
                      .update({'saved_amount': currentAmount + val})
                      .eq('id', id);
                  
                  await Supabase.instance.client.from('transactions').insert({
                    'user_id': userId,
                    'title': 'Deposit to Goal: $goalName',
                    'amount': val,
                    'type': 'expense',
                    'category': 'Savings',
                    'created_at': DateTime.now().toUtc().toIso8601String(),
                  });
                  _fetchGoals();
                } catch (e) {
                  debugPrint("Update error: $e");
                }
              }
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdrawFundsFromGoal(String id, double currentAmount, String goalName) async {
    TextEditingController amountController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Goal Saved: ₱${currentAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(amountController.text.trim());
              if (val != null && val > 0) {
                if (val > currentAmount) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insufficient funds in goal!')));
                  return;
                }
                Navigator.pop(context);
                try {
                  await Supabase.instance.client
                      .from('savings_goals')
                      .update({'saved_amount': currentAmount - val})
                      .eq('id', id);
                  
                  final userId = Supabase.instance.client.auth.currentUser!.id;
                  await Supabase.instance.client.from('transactions').insert({
                    'user_id': userId,
                    'title': 'Withdraw from Goal: $goalName',
                    'amount': val,
                    'type': 'income',
                    'category': 'Savings',
                    'created_at': DateTime.now().toUtc().toIso8601String(),
                  });
                  _fetchGoals();
                } catch (e) {
                  debugPrint("Update error: $e");
                }
              }
            },
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }

  void _showGoalDetailsModal(Map<String, dynamic> goal, double saved) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _GoalDetailsBottomSheet(
        goal: goal,
        onAddFunds: () {
          Navigator.pop(context);
          _addFundsToGoal(goal['id'], saved, goal['name']);
        },
        onWithdrawFunds: () {
          Navigator.pop(context);
          _withdrawFundsFromGoal(goal['id'], saved, goal['name']);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Savings Goals'),
        backgroundColor: const Color(0xFF634DFF),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddGoalModal,
        backgroundColor: const Color(0xFF634DFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(color: Colors.white)),
      ),
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? const Center(child: Text("No goals yet. Add one to start saving!"))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _goals.length,
                  itemBuilder: (context, index) {
                    final goal = _goals[index];
                    final target = (goal['target_amount'] as num).toDouble();
                    final saved = (goal['saved_amount'] as num).toDouble();
                    final percent = (saved / target).clamp(0.0, 1.0);
                    
                    return Dismissible(
                      key: Key(goal['id'].toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteGoal(goal['id'].toString()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showGoalDetailsModal(goal, saved),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(goal['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle, color: Color(0xFF634DFF)),
                                      onPressed: () => _addFundsToGoal(goal['id'], saved, goal['name']),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_currencyFormat.format(saved), style: const TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text('of ${_currencyFormat.format(target)}', style: const TextStyle(color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: 12,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF634DFF)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

class _AddGoalBottomSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddGoalBottomSheet({required this.onSaved});

  @override
  State<_AddGoalBottomSheet> createState() => _AddGoalBottomSheetState();
}

class _AddGoalBottomSheetState extends State<_AddGoalBottomSheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _monthsController = TextEditingController();
  
  bool _isAnalyzing = false;
  Map<String, dynamic>? _plan;

  Future<void> _analyzeGoal() async {
    if (_amountController.text.isEmpty || _monthsController.text.isEmpty) return;
    
    setState(() => _isAnalyzing = true);
    final target = double.tryParse(_amountController.text) ?? 0;
    final months = int.tryParse(_monthsController.text) ?? 1;

    final plan = await FinanceService.suggestGoalPlan(target, months);
    
    if (mounted) {
      setState(() {
        _plan = plan;
        _isAnalyzing = false;
      });
      if (plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate AI plan. Please ensure your backend is running and authenticated via gcloud.')),
        );
      }
    }
  }

  Future<void> _saveGoal() async {
    final name = _nameController.text.trim();
    final target = double.tryParse(_amountController.text) ?? 0;
    
    if (name.isEmpty || target <= 0) return;

    final userId = Supabase.instance.client.auth.currentUser!.id;
    
    await Supabase.instance.client.from('savings_goals').insert({
      'user_id': userId,
      'name': name,
      'target_amount': target,
      'saved_amount': 0.0,
      'deadline_months': int.tryParse(_monthsController.text) ?? 1,
      'weekly_savings': _plan?['weekly_savings'],
      'ai_insight': _plan?['tip'],
    });
    
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create Savings Goal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Goal Name (e.g. New Phone)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target Amount (₱)'),
              onChanged: (_) => setState(() => _plan = null),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _monthsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Deadline (Months)'),
              onChanged: (_) => setState(() => _plan = null),
            ),
            const SizedBox(height: 20),
            if (_isAnalyzing)
              const Center(child: CircularProgressIndicator())
            else if (_plan != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💡 AI Plan: Save ₱${((_plan!['weekly_savings'] as num).toDouble()).toStringAsFixed(2)} per week', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                    const SizedBox(height: 8),
                    Text(_plan!['tip'], style: const TextStyle(color: Colors.black87)),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _analyzeGoal,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate AI Savings Plan'),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveGoal,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF634DFF), foregroundColor: Colors.white),
                child: const Text('Start Saving!'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _GoalDetailsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> goal;
  final VoidCallback onAddFunds;
  final VoidCallback onWithdrawFunds;
  
  const _GoalDetailsBottomSheet({required this.goal, required this.onAddFunds, required this.onWithdrawFunds});

  @override
  State<_GoalDetailsBottomSheet> createState() => _GoalDetailsBottomSheetState();
}

class _GoalDetailsBottomSheetState extends State<_GoalDetailsBottomSheet> {
  bool _isLoading = true;
  Map<String, dynamic>? _plan;

  @override
  void initState() {
    super.initState();
    _fetchInsights();
  }

  Future<void> _fetchInsights() async {
    if (widget.goal['ai_insight'] != null && widget.goal['weekly_savings'] != null) {
      if (mounted) {
        setState(() {
          _plan = {
            'tip': widget.goal['ai_insight'],
            'weekly_savings': widget.goal['weekly_savings'],
          };
          _isLoading = false;
        });
      }
      return;
    }
    
    final target = (widget.goal['target_amount'] as num).toDouble();
    final saved = (widget.goal['saved_amount'] as num).toDouble();
    final remaining = target - saved;
    final plan = await FinanceService.suggestGoalPlan(remaining > 0 ? remaining : target, 1);
    
    if (mounted) {
      setState(() {
        _plan = plan;
        _isLoading = false;
      });
    }
  }

  Future<void> _reevaluatePlan() async {
    setState(() => _isLoading = true);
    final target = (widget.goal['target_amount'] as num).toDouble();
    final saved = (widget.goal['saved_amount'] as num).toDouble();
    final remaining = target - saved;
    final months = widget.goal['deadline_months'] ?? 1;
    
    final newPlan = await FinanceService.suggestGoalPlan(remaining > 0 ? remaining : target, months);
    
    if (newPlan != null && mounted) {
      await Supabase.instance.client.from('savings_goals').update({
        'weekly_savings': newPlan['weekly_savings'],
        'ai_insight': newPlan['tip'],
      }).eq('id', widget.goal['id']);
      
      setState(() {
        _plan = newPlan;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = (widget.goal['target_amount'] as num).toDouble();
    final saved = (widget.goal['saved_amount'] as num).toDouble();
    final isCompleted = saved >= target;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(widget.goal['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              if (widget.goal['deadline_months'] != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                  child: Text('${widget.goal['deadline_months']} Months', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (isCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E62FF), Color(0xFF8C3CFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  const Text('Goal Achieved!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    "You've successfully saved ₱${target.toStringAsFixed(2)}! You can now confidently buy your ${widget.goal['name']}. Treat yourself, you've earned it!",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_plan != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡 AI Insights', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_plan!['tip'], style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text('Suggested weekly savings: ₱${((_plan!['weekly_savings'] as num).toDouble()).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                ],
              ),
            )
          else
            const Text('Failed to load AI insights.', style: TextStyle(color: Colors.red)),
          const SizedBox(height: 24),
          if (isCompleted)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: widget.onWithdrawFunds,
                icon: const Icon(Icons.shopping_bag),
                label: const Text('Withdraw Funds to Buy Item'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onWithdrawFunds,
                        icon: const Icon(Icons.remove),
                        label: const Text('Withdraw'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: widget.onAddFunds,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Funds'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF634DFF), foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: TextButton.icon(
                    onPressed: _reevaluatePlan,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Re-evaluate Plan'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
