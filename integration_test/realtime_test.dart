// test/realtime_integration_test.dart
//
// Run with:  dart test -j1  (single-threaded gives clearer logs)
//
// These are *integration* tests – they will incur real usage on your key!

import 'dart:io';

import 'package:test/test.dart';
import '../lib/openai_client.dart';
import '../lib/audio.dart'; // SpeechVoice, AudioModel, …
import '../lib/realtime.dart'; // the code you pasted
import '../lib/realtime_beta.dart';

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
    test('createCall()', () async {
      final session = await client.createCall(
        sdp: [
          'v=0',
          'o=- 5592595570222642244 2 IN IP4 127.0.0.1',
          's=-',
          't=0 0',
          'a=group:BUNDLE 0',
          'a=extmap-allow-mixed',
          'a=msid-semantic: WMS a17b71f2-adff-4f83-bbe0-66971381888b',
          'm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126',
          'c=IN IP4 0.0.0.0',
          'a=rtcp:9 IN IP4 0.0.0.0',
          'a=ice-ufrag:EZjJ',
          'a=ice-pwd:1ha6g/kCdYeW1ag1vTnDBiy+',
          'a=ice-options:trickle',
          'a=fingerprint:sha-256 A9:26:F9:3A:23:12:61:7E:FF:0B:4B:03:14:BC:40:CD:9A:F4:0D:43:8E:8E:02:CB:5B:FF:67:06:F4:3B:FE:6B',
          'a=setup:actpass',
          'a=mid:0',
          'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level',
          'a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time',
          'a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01',
          'a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid',
          'a=sendonly',
          'a=msid:a17b71f2-adff-4f83-bbe0-66971381888b b7d477c9-fe13-43f4-8015-9f2c9d34744d',
          'a=rtcp-mux',
          'a=rtcp-rsize',
          'a=rtpmap:111 opus/48000/2',
          'a=rtcp-fb:111 transport-cc',
          'a=fmtp:111 minptime=10;useinbandfec=1',
          'a=rtpmap:63 red/48000/2',
          'a=fmtp:63 111/111',
          'a=rtpmap:9 G722/8000',
          'a=rtpmap:0 PCMU/8000',
          'a=rtpmap:8 PCMA/8000',
          'a=rtpmap:13 CN/8000',
          'a=rtpmap:110 telephone-event/48000',
          'a=rtpmap:126 telephone-event/8000',
          'a=ssrc:695023795 cname:kWp1p//QNNbp6m8F',
          'a=ssrc:695023795 msid:a17b71f2-adff-4f83-bbe0-66971381888b b7d477c9-fe13-43f4-8015-9f2c9d34744d',
          ''
        ].join('\r\n'),
        model: RealtimeModel.gptRealtime,
        outputModalities: const [Modality.text, Modality.audio],
        instructions: 'You are a test runner.',
        audio: RealtimeSessionAudio(
          output:
              RealtimeSessionAudioOutput(voice: SpeechVoice.alloy, speed: 1.1),
        ),
        tracing: const TracingAuto(),
      );

      expect(session.callId, isNotNull);
    });

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
        inputAudioFormat: BetaAudioFormat.pcm16,
        inputAudioTranscription: const InputAudioTranscription(
          model: AudioModel.whisper1,
        ),
      );

      expect(tsession.id, startsWith('sess_'));
      expect(tsession.object, equals('realtime.transcription_session'));
      expect(tsession.inputAudioFormat, equals(BetaAudioFormat.pcm16));
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

      expect(sdpAnswer, contains('v=0'),
          reason: 'Should return a valid SDP blob');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
