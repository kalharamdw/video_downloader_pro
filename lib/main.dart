import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Video Downloader Pro',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TextEditingController urlController = TextEditingController();
  List<MuxedStreamInfo> streams = [];
  String status = "";
  bool loading = false;
  double progress = 0;

  Future<void> requestPermission() async {
    await Permission.storage.request();
  }

  // ==================== YouTube ====================
  Future<void> fetchYouTube() async {
    if (urlController.text.isEmpty) {
      setState(() => status = "Please enter URL");
      return;
    }

    setState(() {
      loading = true;
      status = "Fetching YouTube video...";
      streams.clear();
      progress = 0;
    });

    try {
      var yt = YoutubeExplode();
      var video = await yt.videos.get(urlController.text);
      var manifest = await yt.videos.streamsClient.getManifest(video.id);

      // Filter only muxed streams (video + audio)
      streams = manifest.muxed
          .where((s) => ['360p', '480p', '720p'].contains(s.qualityLabel))
          .toList();

      yt.close();

      setState(() {
        status = "Select quality to download";
      });
    } catch (e) {
      setState(() {
        status = "YouTube Error: $e";
      });
    }

    setState(() => loading = false);
  }

  Future<void> downloadYouTube(MuxedStreamInfo streamInfo) async {
    await requestPermission();
    setState(() {
      status = "Downloading...";
      progress = 0;
    });

    try {
      var yt = YoutubeExplode();
      var video = await yt.videos.get(urlController.text);

      String safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");

      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory(); // Android Downloads
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      var file = File("${dir!.path}/$safeTitle.mp4");

      var stream = yt.videos.streamsClient.get(streamInfo);
      var fileStream = file.openWrite();

      int totalBytes = streamInfo.size.totalBytes;
      int received = 0;

      await for (final data in stream) {
        fileStream.add(data);
        received += data.length;
        setState(() {
          progress = received / totalBytes;
        });
      }

      await fileStream.flush();
      await fileStream.close();
      yt.close();

      setState(() {
        status = "Downloaded: ${file.path}";
        progress = 0;
      });
    } catch (e) {
      setState(() {
        status = "Download Error: $e";
        progress = 0;
      });
    }
  }

  // ==================== Facebook ====================
  Future<void> downloadFacebook(String url) async {
    await requestPermission();
    setState(() {
      status = "Fetching Facebook video...";
      progress = 0;
    });

    try {
      var response = await http.get(
        Uri.parse(
            "https://facebook-video-downloader-api.p.rapidapi.com/api?url=$url"),
        headers: {
          "X-RapidAPI-Key": "3d92438e92msh6331104f5e60006p193d23jsnc16bac608758",
          "X-RapidAPI-Host":
          "facebook-video-downloader-api.p.rapidapi.com"
        },
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data["links"] != null) {
          String? videoUrl = data["links"]["hd"] ?? data["links"]["sd"];
          if (videoUrl != null) {
            await downloadDirect(videoUrl);
          } else {
            setState(() => status = "No video quality found");
          }
        } else {
          setState(() => status = "Invalid API response");
        }
      } else {
        setState(() => status = "API Error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => status = "Facebook Error: $e");
    }
  }

  Future<void> downloadDirect(String url) async {
    setState(() {
      status = "Downloading...";
      progress = 0;
    });

    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      var file = File("${dir!.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4");

      var request = await HttpClient().getUrl(Uri.parse(url));
      var response = await request.close();

      List<int> bytes = [];
      int total = response.contentLength;
      int received = 0;

      await for (var data in response) {
        bytes.addAll(data);
        received += data.length;
        setState(() {
          if (total > 0) progress = received / total;
        });
      }

      await file.writeAsBytes(bytes);

      setState(() {
        status = "Downloaded: ${file.path}";
        progress = 0;
      });
    } catch (e) {
      setState(() {
        status = "Download Error: $e";
        progress = 0;
      });
    }
  }

  void handleDownload() {
    String url = urlController.text.trim();
    if (url.isEmpty) {
      setState(() => status = "Paste a URL first");
      return;
    }
    if (url.contains("youtube.com") || url.contains("youtu.be")) {
      fetchYouTube();
    } else if (url.contains("facebook.com")) {
      downloadFacebook(url);
    } else {
      setState(() => status = "Unsupported URL");
    }
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Video Downloader Pro")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: "Paste YouTube / Facebook URL",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.download),
              onPressed: handleDownload,
              label: Text("Fetch Video"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
            SizedBox(height: 12),
            if (loading) CircularProgressIndicator(),
            if (streams.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: streams.length,
                  itemBuilder: (context, index) {
                    var stream = streams[index];
                    return Card(
                      elevation: 3,
                      margin: EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                        leading: Icon(Icons.video_label),
                        title: Text("${stream.qualityLabel}"),
                        trailing: Icon(Icons.download),
                        onTap: () => downloadYouTube(stream),
                      ),
                    );
                  },
                ),
              ),
            SizedBox(height: 12),
            if (progress > 0)
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
              ),
            SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}