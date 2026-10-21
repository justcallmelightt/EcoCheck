import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showingPreview = false

    private let background = Color(red: 245/255, green: 247/255, blue: 249/255)
    private let lime = Color(red: 192/255, green: 251/255, blue: 62/255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Image("EcoCheckLogo")
                        .resizable().scaledToFit()
                        .frame(width: 172, height: 57)
                        .accessibilityLabel("EcoCheck")
                    Spacer()
                }
                Text("HI, USER!")
                    .font(.custom("Pretendard-Medium", size: 20))
                    .tracking(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 15)
                    .padding(.top, 8)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 8) {
                            Capsule()
                                .fill(LinearGradient(colors: [lime, .clear], startPoint: .top, endPoint: .bottom))
                                .frame(width: 9, height: 56).padding(.top, 9)
                            Text("0g")
                                .font(.custom("Pretendard-ExtraBold", size: 73))
                                .tracking(-1.5)
                        }
                        Text("지금까지\n절약한 CO₂")
                            .font(.custom("Pretendard-SemiBold", size: 17))
                            .foregroundStyle(.gray)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.leading, 22)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .leading, spacing: 18) {
                        metric("leaf", "0", "리사이클")
                        metric("dollarsign.circle", "0", "포인트")
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 42)
                .padding(.horizontal, 9)

                Image("HomeBottle")
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Text("지금 스캔하고\n분리배출을 확인해보세요!")
                            .font(.custom("Pretendard-SemiBold", size: 21))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 28))
                            .frame(width: 60, height: 60)
                            .background(.white.opacity(0.13), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color(red: 30/255, green: 32/255, blue: 31/255), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사진을 선택해 분리배출 확인하기")
                .padding(.horizontal, 4)

                HStack {
                    tab("house.fill", "홈", selected: true)
                    tab("clock.fill", "기록")
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        VStack(spacing: 2) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 31))
                                .frame(width: 61, height: 61)
                                .background(lime, in: Circle())
                            Text("스캔").font(.custom("Pretendard-Medium", size: 12))
                        }
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("스캔할 사진 선택")
                    tab("mappin", "지도")
                    tab("person", "마이페이지")
                }
                .frame(height: 90)
                .background(.white, in: RoundedRectangle(cornerRadius: 25))
                .padding(.top, 15)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 460)
                    }
                    Text("선택한 사진").font(.custom("Pretendard-Bold", size: 22))
                    Text("사진 분석은 다음 단계에서 연결합니다.")
                        .font(.custom("Pretendard-Regular", size: 16))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("스캔").font(.custom("Pretendard-SemiBold", size: 17))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showingPreview = false }
                            .font(.custom("Pretendard-Medium", size: 16))
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                guard let data = try? await newPhoto?.loadTransferable(type: Data.self),
                      let loadedImage = UIImage(data: data) else { return }
                image = loadedImage
                showingPreview = true
            }
        }
    }

    private func metric(_ symbol: String, _ value: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 31, height: 31)
                .background(lime.opacity(0.35), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.custom("Pretendard-Bold", size: 30))
                Text(title).font(.custom("Pretendard-SemiBold", size: 15)).foregroundStyle(.gray)
            }
        }
    }

    private func tab(_ symbol: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 27)).frame(height: 39)
            Text(title).font(.custom("Pretendard-Medium", size: 12))
        }
        .foregroundStyle(selected ? Color.black : Color.gray)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
