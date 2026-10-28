import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_system.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _agreed = false;
  bool _loading = false;

  Future<void> _accept() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先阅读并勾选同意隐私协议')));
      return;
    }
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_consent_v1', true);
    if (!mounted) return;
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('隐私保护')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: AppGradients.glass,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(Icons.shield_rounded, size: 50, color: AppColors.blue),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '隐私保护与授权',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            const Text(
              '先了解我们如何保护你的人脸信息',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            AppGlassCard(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
              child: Column(
                children: const [
                  _PrivacyItem(index: '1', text: '人脸信息仅用于本应用登录身份核验。'),
                  _PrivacyItem(index: '2', text: '人脸信息会加密保存，不用于广告或营销。'),
                  _PrivacyItem(index: '3', text: '你可以随时在“人脸管理”中查看或删除。'),
                  _PrivacyItem(index: '4', text: '删除后仍可使用手机号验证码登录。'),
                  _PrivacyItem(index: '5', text: '多次刷脸失败会临时停用刷脸登录。'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppGlassCard(
              radius: 19,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onTap: () => setState(() => _agreed = !_agreed),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: _agreed ? AppGradients.primaryButton : null,
                      color: _agreed ? null : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _agreed ? Colors.transparent : const Color(0xFFB7CBDD),
                        width: 1.3,
                      ),
                    ),
                    child: _agreed
                        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '我已阅读并同意《人脸识别隐私协议》',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppGradientButton(
              label: '同意并继续',
              icon: Icons.check_circle_rounded,
              loading: _loading,
              onPressed: _loading ? null : _accept,
            ),
            const SizedBox(height: 10),
            const Text(
              '你可以稍后在“我的 → 人脸数据管理”中撤回授权',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted2),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyItem extends StatelessWidget {
  const _PrivacyItem({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF2F83D2),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.55, color: Color(0xFF385B7E)),
            ),
          ),
        ],
      ),
    );
  }
}
