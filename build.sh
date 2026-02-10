set -eux
set -o pipefail

swift build --configuration release --arch x86_64 --arch arm64

cp ./.build/apple/Products/Release/LRExportHEIC ./LRExportHEIC
