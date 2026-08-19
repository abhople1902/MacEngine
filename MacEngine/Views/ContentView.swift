//
//  ContentView.swift
//  MacEngine
//
//  Created by Ayush Bhople on 20/08/26.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: DashboardViewModel

    var body: some View {
        DashboardView(model: model)
            .frame(minWidth: 640, minHeight: 560)
            .onAppear { model.start() }
    }
}

#Preview {
    ContentView(model: DashboardViewModel())
}
