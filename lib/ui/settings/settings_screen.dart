import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/chat_prefs_store.dart';
import '../../data/followed_chats_store.dart';
import '../../tdlib/telegram_client.dart';
import '../../theme/app_theme.dart';
import '../picker/group_picker_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final chatPrefs = context.watch<ChatPrefsStore>();
    final store = context.watch<FollowedChatsStore>();
    final client = context.watch<TelegramClient>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Appearance', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('System')),
              ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (value) {
              settings.setThemeMode(value.first);
            },
          ),
          const SizedBox(height: 28),
          Text('Accent color', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppAccentColor.values.map((accent) {
              final (primary, _) = AppTheme.colorsFor(accent);
              final selected = settings.accentColor == accent;
              return ChoiceChip(
                label: Text(accent.name),
                selected: selected,
                avatar: CircleAvatar(backgroundColor: primary, radius: 8),
                onSelected: (_) => settings.setAccentColor(accent),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text('Notifications', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Mentions only'),
            subtitle: const Text(
              'Notify only when a message mentions you',
            ),
            value: chatPrefs.mentionsOnly,
            onChanged: chatPrefs.setMentionsOnly,
          ),
          SwitchListTile(
            title: const Text('Hide message preview'),
            subtitle: const Text(
              'Default for new chats; show title only in notifications',
            ),
            value: chatPrefs.defaultHidePreview,
            onChanged: chatPrefs.setDefaultHidePreview,
          ),
          const SizedBox(height: 28),
          Text('Groups', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Manage followed groups'),
              subtitle: Text(
                '${store.ids.length} followed · ${store.mutedIds.length} muted',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GroupPickerScreen(allowSkip: true),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Text('Account', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Log out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Log out?'),
                    content: const Text(
                      'You will need to sign in with your phone again.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Log out'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await client.logOut();
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'TG Focus keeps only the chats you pick — a quieter Telegram.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
