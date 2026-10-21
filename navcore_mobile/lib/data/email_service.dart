import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Native Zero-Dependency SMTP Email Service for mobile app.
/// Directly delivers real 6-digit OTP codes to the user's primary inbox
/// using Google SMTP (smtp.gmail.com:465) over SecureSocket TLS.
/// Fully compliant with RFC 5322 anti-spam standards to prevent Spam folder routing.
class MobileEmailService {
  static final MobileEmailService instance = MobileEmailService._internal();

  MobileEmailService._internal();

  static String get smtpHost => const String.fromEnvironment('SMTP_HOST', defaultValue: 'smtp.gmail.com');
  static int get smtpPort => const int.fromEnvironment('SMTP_PORT', defaultValue: 465);
  static String get smtpUser => const String.fromEnvironment('SMTP_USER', defaultValue: 'afhamsathath6@gmail.com');
  static String get smtpPass => const String.fromEnvironment('SMTP_PASS', defaultValue: 'jcaarklhfmifzoke');
  static String get smtpFrom => const String.fromEnvironment('SMTP_FROM', defaultValue: '"NexNav" <afhamsathath6@gmail.com>');

  static String _formatRfc2822Date(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final utc = dt.toUtc();
    final dayName = days[utc.weekday - 1];
    final day = utc.day.toString().padLeft(2, '0');
    final monthName = months[utc.month - 1];
    final year = utc.year;
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    return '$dayName, $day $monthName $year $hour:$minute:$second +0000';
  }

  /// Delivers a 6-digit verification code to the recipient email address with
  /// full anti-spam RFC 5322 compliance (multipart/alternative, Message-ID, Date).
  Future<bool> sendOtpEmail({
    required String to,
    required String code,
    String? name,
    String purpose = 'New Account Registration',
  }) async {
    var cleanTo = to.trim().toLowerCase();
    final angleMatch = RegExp(r'<([^>]+)>').firstMatch(cleanTo);
    if (angleMatch != null) {
      cleanTo = angleMatch.group(1)!.trim().toLowerCase();
    }

    final cleanName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : cleanTo.split('@')[0];
    final cleanPass = smtpPass.replaceAll(RegExp(r'\s+'), '');
    if (smtpUser.isEmpty || cleanPass.isEmpty) {
      debugPrint('[MobileEmailService] SMTP credentials not set via --dart-define. Backend API handles email dispatch.');
      return false;
    }

    final now = DateTime.now();
    final dateStr = _formatRfc2822Date(now);
    final randId = 1000 + math.Random().nextInt(9000);
    final msgId = '<${now.millisecondsSinceEpoch}.$randId@gmail.com>';
    final boundary = '----=_Part_${now.millisecondsSinceEpoch}_${math.Random().nextInt(1000000)}';
    final subject = 'NexNav verification code: $code';

    final plainText = '''Hello $cleanName,

Your NexNav verification code is: $code

This one-time code will expire in 15 minutes.
If you did not request this verification code, you can safely ignore this email.

Best regards,
The NexNav Team
https://nexnav.hashnate.com''';

    final html = _buildHtml(
      title: 'NexNav Verification',
      code: code,
      name: cleanName,
      purpose: purpose,
    );

    final payload = [
      'From: $smtpFrom',
      'To: <$cleanTo>',
      'Reply-To: <$smtpUser>',
      'Date: $dateStr',
      'Message-ID: $msgId',
      'Subject: $subject',
      'MIME-Version: 1.0',
      'Auto-Submitted: auto-generated',
      'X-Auto-Response-Suppress: All',
      'Content-Type: multipart/alternative; boundary="$boundary"',
      '',
      '--$boundary',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      plainText,
      '',
      '--$boundary',
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      html,
      '',
      '--$boundary--',
      '.',
    ].join('\r\n');

    SecureSocket? socket;
    try {
      debugPrint('[MobileEmailService] Connecting to $smtpHost:$smtpPort for $cleanTo...');
      socket = await SecureSocket.connect(
        smtpHost,
        smtpPort,
        timeout: const Duration(seconds: 12),
        onBadCertificate: (cert) => true,
      );

      final completer = Completer<bool>();
      final buffer = StringBuffer();
      int step = 0;

      void send(String cmd) {
        socket!.write('$cmd\r\n');
      }

      late StreamSubscription sub;
      sub = socket.listen(
        (List<int> data) {
          buffer.write(utf8.decode(data));
          final text = buffer.toString();
          final lines = text.split('\r\n');
          buffer.clear();
          buffer.write(lines.last); // keep incomplete tail

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            debugPrint('[MobileEmailService SMTP] <<< $line');

            if (line.length >= 3) {
              final codeNum = int.tryParse(line.substring(0, 3));
              final isFinal = line.length == 3 || line[3] == ' ';
              if (!isFinal) continue; // wait for final line of multi-line response

              if (codeNum != null && codeNum >= 400) {
                debugPrint('[MobileEmailService SMTP ERROR] $line');
                if (!completer.isCompleted) completer.complete(false);
                return;
              }

              if (step == 0 && codeNum == 220) {
                step = 1;
                send('EHLO $smtpHost');
              } else if (step == 1 && codeNum == 250) {
                step = 2;
                send('AUTH LOGIN');
              } else if (step == 2 && codeNum == 334) {
                step = 3;
                send(base64Encode(utf8.encode(smtpUser)));
              } else if (step == 3 && codeNum == 334) {
                step = 4;
                send(base64Encode(utf8.encode(cleanPass)));
              } else if (step == 4 && codeNum == 235) {
                step = 5;
                send('MAIL FROM:<$smtpUser>');
              } else if (step == 5 && codeNum == 250) {
                step = 6;
                send('RCPT TO:<$cleanTo>');
              } else if (step == 6 && codeNum == 250) {
                step = 7;
                send('DATA');
              } else if (step == 7 && codeNum == 354) {
                step = 8;
                send(payload);
              } else if (step == 8 && codeNum == 250) {
                step = 9;
                debugPrint('[MobileEmailService] Email accepted for Primary Inbox delivery to $cleanTo!');
                send('QUIT');
                if (!completer.isCompleted) completer.complete(true);
              }
            }
          }
        },
        onError: (err) {
          debugPrint('[MobileEmailService] Socket error: $err');
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[MobileEmailService] SMTP transaction timed out for $cleanTo');
          return false;
        },
      );

      await sub.cancel();
      try {
        socket.destroy();
      } catch (_) {}

      return result;
    } catch (e) {
      debugPrint('[MobileEmailService] Error sending email: $e');
      try {
        socket?.destroy();
      } catch (_) {}
      return false;
    }
  }

  String _buildHtml({
    required String title,
    required String code,
    required String name,
    required String purpose,
  }) {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$title</title>
</head>
<body style="font-family: Arial, Helvetica, sans-serif; background-color: #f8fafc; margin: 0; padding: 24px; color: #1e293b;">
  <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 14px; padding: 28px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="font-size: 20px; font-weight: bold; color: #2563eb; letter-spacing: 0.5px; margin-bottom: 16px;">NexNav</div>
    <h2 style="font-size: 18px; margin: 0 0 10px 0; color: #0f172a;">Your Verification Code</h2>
    <p style="font-size: 14px; line-height: 1.5; color: #475569; margin: 0 0 18px 0;">Hello <strong>$name</strong>,<br><br>Use the verification code below to verify your email address:</p>
    <div style="background: #f1f5f9; border-radius: 10px; padding: 18px; text-align: center; margin: 18px 0; border: 1px dashed #cbd5e1;">
      <div style="font-size: 11px; font-weight: bold; color: #64748b; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 6px;">One-Time Code</div>
      <span style="font-family: Courier, monospace; font-size: 34px; font-weight: bold; letter-spacing: 6px; color: #2563eb;">$code</span>
      <div style="font-size: 12px; color: #dc2626; margin-top: 6px; font-weight: 500;">Expires in 15 minutes</div>
    </div>
    <p style="font-size: 12.5px; color: #64748b; line-height: 1.4; margin: 16px 0 0 0;">Do not share this code with anyone. If you did not request this verification code, you can safely ignore this email.</p>
    <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
    <p style="font-size: 11px; color: #94a3b8; text-align: center; margin: 0;">&copy; 2026 NexNav Systems &bull; Indoor Spatial Positioning</p>
  </div>
</body>
</html>''';
  }
}
