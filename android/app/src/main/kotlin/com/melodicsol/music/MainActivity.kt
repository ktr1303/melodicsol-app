package com.melodicsol.music

import io.flutter.embedding.android.FlutterActivity
import com.ryanheise.audioservice.AudioServiceActivity   // ← This is the key line

class MainActivity: AudioServiceActivity() {   // ← Change to AudioServiceActivity
}