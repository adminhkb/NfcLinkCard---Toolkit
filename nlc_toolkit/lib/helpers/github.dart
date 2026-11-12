import 'dart:convert';
import 'dart:typed_data';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:http/http.dart' as http;

// Micrologiciel du ChameleonUltra : publications et compilations du fabricant (RfidResearchGroup).
Future<Uint8List> fetchFirmwareFromReleases(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["prerelease"]) {
        for (var file in release["assets"]) {
          if (file["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
            content =
                await http.readBytes(Uri.parse(file["browser_download_url"]));
            break;
          }
        }
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<Uint8List> fetchFirmwareFromActions(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts?per_page=100")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main" &&
          artifact["workflow_run"]["head_repository_id"] == 581338100) {
        content = await http.readBytes(Uri.parse(
            "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/${artifact["workflow_run"]["id"]}/artifacts/${artifact["id"]}"));
        break;
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<String> latestAvailableCommit(ChameleonDevice device) async {
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts?per_page=100")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main" &&
          artifact["workflow_run"]["head_repository_id"] == 581338100) {
        return artifact["workflow_run"]["head_sha"];
      }
    }
  } catch (_) {}

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["author"]["login"] == "github-actions[bot]" &&
          release["prerelease"]) {
        return release["target_commitish"];
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return "";
}

Future<String> resolveCommit(String commitHash) async {
  if ('-'.allMatches(commitHash).length == 2) {
    return commitHash.split("-")[2].replaceAll('g', ''); // v2.0.0-1-gXXXXXX
  } else if (commitHash.startsWith('-dirty')) {
    return commitHash; // v2.0.0-1-gXXXXXX-dirty
  } else if ('-'.allMatches(commitHash).isEmpty) {
    final tags = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/tags")))
        .body
        .toString());
    for (var tag in tags) {
      if (commitHash == tag['name']) {
        return tag['commit']['sha'];
      }
    }
  }

  return commitHash;
}
