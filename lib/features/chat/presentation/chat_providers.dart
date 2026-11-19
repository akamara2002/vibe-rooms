import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../data/supabase_chat_repository.dart';
import '../data/unconfigured_chat_repository.dart';
import '../domain/chat_repository.dart';
import 'chat_controller.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (!ref.watch(supabaseReadyProvider)) {
    return const UnconfiguredChatRepository();
  }
  return SupabaseChatRepository(Supabase.instance.client);
});

/// One per room visit. The room screen keeps it alive, so messages and the
/// unread count keep arriving while another tab is open.
final chatControllerProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatState, String>(ChatController.new);
