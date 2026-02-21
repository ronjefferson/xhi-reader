# xHi-Reader

An offline-first e-reader built with Flutter, backed by a custom backend for book storage and cross-device synchronization.

## Features

- Supports **EPUB and PDF** formats  
- PDF rendering powered by Pdfium (via pdfrx)  
- Downloads and stores books locally for instant offline access  
- Reading progress persisted locally using SQLite  
- Automatic background synchronization of reading position (page, chapter, scroll percentage) with the backend  
- Book storage and retrieval through a custom API    
- Dynamic dark mode support with injected CSS for EPUB content  

## Tech Stack
* [![Flutter][Flutter-badge]][Flutter-url]
* [![Dart][Dart-badge]][Dart-url]
* [![SQLite][SQLite-badge]][SQLite-url]
* [![Android][Android-badge]][Android-url]
* [![iOS][iOS-badge]][iOS-url]

## Getting Started

### Prerequisites
* Flutter SDK (Version 3.10+)

### Installation

1. Clone the repository:
   ```git clone https://github.com/yourusername/your-repo-name.git```

2. Navigate to the project directory:
   ```cd your-repo-name```

3. Install dependencies:
   ```flutter pub get```

4. Run the app:
   ```flutter run```


[Flutter-badge]: https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white
[Flutter-url]: https://flutter.dev/
[Dart-badge]: https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white
[Dart-url]: https://dart.dev/
[SQLite-badge]: https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white
[SQLite-url]: https://www.sqlite.org/
[Android-badge]: https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white
[Android-url]: https://developer.android.com/
[iOS-badge]: https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white
[iOS-url]: https://developer.apple.com/ios/