import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../finance_service.dart';

// Provides the current user session
final authProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// Provides the user's transactions
final transactionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return [];
  
  final response = await Supabase.instance.client
      .from('transactions')
      .select('*')
      .eq('user_id', session.user.id)
      .order('created_at', ascending: false);
      
  return List<Map<String, dynamic>>.from(response);
});

// Provides the user's budget limits (caches in memory via Riverpod)
final budgetLimitsProvider = FutureProvider<Map<String, double>>((ref) async {
  return await FinanceService.getBudgets();
});

