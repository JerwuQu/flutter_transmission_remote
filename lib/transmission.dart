import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/http.dart';

enum TorrentStatus {
  stopped,
  queuedToCheck,
  checking,
  queuedToDownload,
  downloading,
  queuedToSeed,
  seeding;

  String prettyName() {
    return name[0].toUpperCase() + name.substring(1);
  }
}

class TransmissionException implements Exception {
  String message;
  TransmissionException(this.message);
}

class Torrent {
  int id, addedDate;
  TorrentStatus status;
  String name, downloadDir, errorString;
  int? size, bytesLeft, seeds, leeches, downSpeed, upSpeed, downTotal, upTotal;
  Torrent.fromJson(dynamic json)
      : addedDate = json['addedDate'],
        bytesLeft = json['leftUntilDone'],
        downloadDir = json['downloadDir'],
        downSpeed = json['rateDownload'],
        downTotal = json['downloadedEver'],
        errorString = json['errorString'],
        leeches = json['peersGettingFromUs'],
        name = json['name'],
        seeds = json['peersSendingToUs'],
        size = json['sizeWhenDone'],
        status = TorrentStatus.values[json['status']],
        upSpeed = json['rateUpload'],
        upTotal = json['uploadedEver'],
        id = json['id'];
}

class TransmissionConnection {
  Uri rpcUri;
  String username, password;
  String? sessionId;

  TransmissionConnection(String rpcUrl, this.username, this.password) : rpcUri = Uri.parse(rpcUrl);

  Future<dynamic> tFetch(dynamic body, [bool isRetry = false]) async {
    Map<String, String> headers = {
      'user-agent': 'transmission_remote',
      'content-type': 'application/json',
    };
    if (username.isNotEmpty || password.isNotEmpty) {
      headers['authorization'] = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    }
    if (sessionId != null) {
      headers['x-transmission-session-id'] = sessionId!;
    }

    Response resp;
    try {
      resp = await http.post(
        rpcUri,
        body: jsonEncode(body),
        headers: headers,
      );
    } catch (e) {
      throw TransmissionException('Failed to connect to host');
    }
    if (resp.statusCode == 401) {
      throw TransmissionException('Invalid username/password');
    } else if (resp.statusCode == 409) {
      if (isRetry) {
        throw TransmissionException('Transmission keeps asking to change session id');
      }
      sessionId = resp.headers['x-transmission-session-id'];
      return await tFetch(body, true);
    } else if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw TransmissionException('Invalid response. Not a valid RPC url?');
    }

    dynamic res;
    try {
      res = jsonDecode(resp.body);
    } catch (e) {
      throw TransmissionException('Invalid response. Not a valid RPC url?');
    }
    if (res['result'] == 'success') {
      return res['arguments'];
    } else {
      throw TransmissionException('Transmission rejected API request');
    }
  }

  Future<List<Torrent>> getTorrents() async {
    final resp = await tFetch({
      'method': 'torrent-get',
      'arguments': {
        'fields': [
          'addedDate',
          'downloadDir',
          'downloadedEver',
          'errorString',
          'eta',
          'id',
          'leftUntilDone',
          'name',
          'peersGettingFromUs',
          'peersSendingToUs',
          'rateDownload',
          'rateUpload',
          'recheckProgress',
          'sizeWhenDone',
          'status',
          'uploadedEver',
        ]
      },
    });
    List<dynamic> torrentsJson = resp['torrents'];
    final torrents = torrentsJson.map<Torrent>((json) => Torrent.fromJson(json)).toList();
    torrents.sort((t1, t2) => t2.addedDate - t1.addedDate);
    return torrents;
  }

  Future addTorrentByUrl(String torrentUrl, String downloadDir) async {
    await tFetch({
      'method': 'torrent-add',
      'arguments': {
        'filename': torrentUrl,
        'download-dir': downloadDir,
      }
    });
  }

  Future addTorrentFromFile(Uint8List bytes, String downloadDir) async {
    await tFetch({
      'method': 'torrent-add',
      'arguments': {
        'metainfo': base64Encode(bytes),
        'download-dir': downloadDir,
      }
    });
  }

  Future stopTorrent(int id) async {
    await tFetch({
      'method': 'torrent-stop',
      'arguments': {
        'ids': [id],
      }
    });
  }

  Future startTorrent(int id) async {
    await tFetch({
      'method': 'torrent-start',
      'arguments': {
        'ids': [id],
      }
    });
  }

  Future moveTorrent(int id, String dir) async {
    await tFetch({
      'method': 'torrent-set-location',
      'arguments': {
        'ids': [id],
        'location': dir,
        'move': true,
      }
    });
  }

  Future reannounceTorrent(int id) async {
    await tFetch({
      'method': 'torrent-reannounce',
      'arguments': {
        'ids': [id],
      }
    });
  }

  Future verifyTorrent(int id) async {
    await tFetch({
      'method': 'torrent-verify',
      'arguments': {
        'ids': [id],
      }
    });
  }

  Future removeTorrent(int id, [bool deleteData = false]) async {
    await tFetch({
      'method': 'torrent-remove',
      'arguments': {
        'ids': [id],
        'delete-local-data': deleteData,
      }
    });
  }
}
