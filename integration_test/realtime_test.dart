// test/realtime_integration_test.dart
//
// Run with:  dart test -j1  (single-threaded gives clearer logs)
//
// These are *integration* tests – they will incur real usage on your key!

import 'dart:io';

import 'package:test/test.dart';
import 'package:openai/openai_client.dart';
import 'package:openai/audio.dart'; // SpeechVoice, AudioModel, …
import 'package:openai/realtime.dart'; // the code you pasted

void main() {
  final apiKey = Platform.environment['OPENAI_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️  OPENAI_API_KEY not set – realtime integration tests skipped.');
    return;
  }

  late OpenAIClient client;

  setUpAll(() {
    client = OpenAIClient(apiKey: apiKey);
  });

  tearDownAll(() async {
    client.close();
  });

  group('Realtime integration', () {
    test('createRealtimeSession()', () async {
      final session = await client.createRealtimeSession(
        model: RealtimeModel.gpt4oRealtimePreview,
        modalities: const [Modality.audio, Modality.text],
        instructions: 'You are a test runner.',
        voice: SpeechVoice.alloy,
        temperature: 0.7,
        speed: 1.1,
        tracing: const TracingAuto(),
        // keep the session cheap & tiny
        maxResponseOutputTokens: 64,
      );

      expect(session.id, startsWith('sess_'));
      expect(session.object, equals('realtime.session'));
      expect(session.voice, equals(SpeechVoice.alloy));
      expect(session.clientSecret, isNotNull,
          reason: 'REST create should return an ephemeral key');
    });

    test('createRealtimeTranscriptionSession()', () async {
      final tsession = await client.createRealtimeTranscriptionSession(
        inputAudioFormat: AudioFormat.pcm16,
        inputAudioTranscription: const InputAudioTranscription(
          model: AudioModel.whisper1,
        ),
      );

      expect(tsession.id, startsWith('sess_'));
      expect(tsession.object, equals('realtime.transcription_session'));
      expect(tsession.inputAudioFormat, equals(AudioFormat.pcm16));
    });

    test('getRealtimeSDP()', () async {
      // 1. create an assistant session just to get an api-key for the SDP call
      final s = await client.createRealtimeSession(
        model: RealtimeModel.gpt4oRealtimePreview,
        modalities: const [Modality.audio, Modality.text],
        tracing: const TracingDisabled(),
      );

      final sdpOffer = [
        'v=0',
        'o=- 0 0 IN IP4 127.0.0.1',
        's=-',
        't=0 0',

        // Bundle & stream semantics
        'a=group:BUNDLE 0',
        'a=msid-semantic: WMS *',

        // ---- media section ---------------------------------------------------
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'c=IN IP4 0.0.0.0',
        'a=rtcp:9 IN IP4 0.0.0.0',

        // ICE + DTLS (required)
        'a=ice-ufrag:ufrag123',
        'a=ice-pwd:pwdpwdpwdpwdpwdpwdpwdpwd',
        'a=fingerprint:sha-256 '
            '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:'
            '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF',

        // DTLS role
        'a=setup:actpass',

        // Stream identifiers
        'a=mid:0',
        'a=sendrecv',
        'a=rtpmap:111 opus/48000/2',

        // one SSRC just to keep parsers happy
        'a=ssrc:1 cname:realtime_test',
        '' // <— final CR-LF terminator
      ].join('\r\n');

      final sdpAnswer = await client.getRealtimeSDP(
        model: RealtimeModel.gpt4oRealtimePreview,
        sdp: sdpOffer,
        ephemeralKey: s.clientSecret!.value,
      );

      print(sdpAnswer);

      expect(sdpAnswer, contains('v=0'),
          reason: 'Should return a valid SDP blob');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
