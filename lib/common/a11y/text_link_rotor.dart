import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class A11yTextLink {
  const A11yTextLink(this.label, this.activate);
  final String label;
  final VoidCallback activate;
}

/// Rotor-only targets stay out of the ordinary swipe/read-all semantics tree.
class TextLinkRotor extends StatefulWidget {
  const TextLinkRotor({
    super.key,
    required this.identifier,
    required this.links,
    required this.builder,
  });
  final String identifier;
  final List<A11yTextLink> links;
  final Widget Function(VoidCallback focus) builder;
  @override
  State<TextLinkRotor> createState() => _TextLinkRotorState();
}

class _TextLinkRotorState extends State<TextLinkRotor> {
  static const _channel = MethodChannel('accessibilibili/text_link_rotor');
  static _TextLinkRotorState? _active;
  static int _nextId = 0;
  final int _id = _nextId++;
  List<A11yTextLink> _focusedLinks = const [];

  void _focus() {
    if (!Platform.isIOS) return;
    _active = this;
    _focusedLinks = List.of(widget.links);
    _channel.setMethodCallHandler((call) async {
      final state = _active;
      final args = call.arguments;
      if (call.method != 'activate' ||
          state == null ||
          !state.mounted ||
          args is! Map ||
          args['id'] != state._id)
        return;
      final index = args['index'];
      if (index is int && index >= 0 && index < state._focusedLinks.length) {
        state._focusedLinks[index].activate();
      }
    });
    _send('focus', {
      'id': _id,
      'identifier': widget.identifier,
      'labels': widget.links.map((link) => link.label).toList(),
    });
  }

  Future<void> _send(String method, Object arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (_) {
      // Native rotor availability must not interrupt normal comment reading.
    } on MissingPluginException catch (_) {}
  }

  @override
  void dispose() {
    if (Platform.isIOS && _active == this) {
      _active = null;
      _send('clear', _id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_focus);
}
