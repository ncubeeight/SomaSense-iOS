import SwiftUI

/// The report form, for a new report or an edit.
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focus: ChoiceKind?

    var body: some View {
        @Bindable var model = model
        let editing = model.editing != nil
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { model.formBack() } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(editing ? "Cancel editing" : "Back to body map")
                Text(editing ? "Edit report" : "New report").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    whereSection
                    whenSection
                    choiceSection(.cats, title: "Symptom or sensation type", field: "Other type")
                    textSection("Description", text: $model.form.desc, prompt: "What does it feel or look like?")
                    severitySection
                    medSection
                    choiceSection(.acts, title: "Physical activity at the time", field: "Other activity")
                    senseSection
                    textSection("Concerns", text: $model.form.concern, prompt: "Anything you want to raise with your clinician")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                if let hint = model.saveHint {
                    Text(hint).font(.subheadline).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                }
                Button { focus = nil; model.saveReport() } label: {
                    Text(editing ? "Save changes" : "Save report")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(model.saveHint == nil ? .white : Ink.muted)
                        .background(model.saveHint == nil ? Ink.teal : Ink.disabled, in: Capsule())
                }
                .disabled(model.saveHint != nil)
            }
            .padding(20)
            .background(.white)
        }
        .background(Color.white)
        .foregroundStyle(Ink.text)
        .onChange(of: focus) { old, _ in if let old { model.commitTyped(old) } }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Where")
            FlowLayout {
                ForEach(Array(model.selected.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Ink.teal, in: Circle())
                        Text(p.label)
                        Button { model.removePin(p.id) } label: { Image(systemName: "xmark").font(.caption.bold()).frame(width: 32, height: 32) }
                            .accessibilityLabel("Remove " + p.label)
                    }
                    .padding(.leading, 8)
                    .frame(minHeight: 44)
                    .background(Ink.stage, in: Capsule())
                }
                Button("Add point") { model.composing = false }
                    .frame(minHeight: 44).padding(.horizontal, 14)
                    .foregroundStyle(Ink.teal)
                    .overlay(Capsule().stroke(Ink.teal, lineWidth: 1))
            }
        }
    }

    private var whenSection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "When")
            HStack {
                Text(Day.long(model.homeDay))
                Spacer()
                Text(Words.partOfDay(model.form.time)).foregroundStyle(Ink.muted)
                DatePicker("Time of day", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let p = model.form.time.split(separator: ":").compactMap { Int($0) }
                return Day.calendar.date(bySettingHour: p.first ?? 12, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Day.calendar.dateComponents([.hour, .minute], from: d)
                model.form.time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            })
    }

    private var severitySection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Severity")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.form.severity)").font(.largeTitle.bold())
                Text("out of 10 · " + Words.severity(model.form.severity)).foregroundStyle(Ink.muted)
            }
            Slider(value: Binding(get: { Double(model.form.severity) }, set: { model.form.severity = Int($0.rounded()) }), in: 1...10, step: 1)
                .tint(Ink.teal)
                .accessibilityLabel("Severity from 1 to 10")
                .accessibilityValue("\(model.form.severity), " + Words.severity(model.form.severity))
            HStack {
                Text("Barely noticeable")
                Spacer()
                Text("Worst imaginable")
            }
            .font(.caption).foregroundStyle(Ink.muted)
            Text("Severity notes").font(.subheadline.weight(.semibold)).padding(.top, 6)
            field(text: $model.form.sevNote, prompt: "Constant or in waves? Does it stop you doing anything?")
        }
    }

    private var medSection: some View {
        let chips = model.formChips(.meds)
        return choiceSection(.meds, title: "Medicines taken", field: chips.isEmpty ? "Medicine and dose" : "Other medicine or dose",
                             empty: "Medicines you enter are kept here to choose next time.")
    }

    private var senseSection: some View {
        let chips = model.formChips(.senses)
        return choiceSection(.senses, title: "Other sensations", field: chips.isEmpty ? "Anything else you noticed" : "Something else you noticed",
                             empty: "Sensations you enter are kept here to choose next time.")
    }

    private func choiceSection(_ kind: ChoiceKind, title: String, field label: String, empty: String? = nil) -> some View {
        let chips = model.formChips(kind)
        let chosen = model.form.chosen(kind)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            if chips.isEmpty, let empty {
                Text(empty).font(.subheadline).foregroundStyle(Ink.muted)
            } else {
                FlowLayout {
                    ForEach(chips, id: \.self) { c in
                        HStack(spacing: 0) {
                            Chip(label: c, on: chosen.contains(c)) { model.toggle(kind, c) }
                            Button { model.hideChoice(kind, c) } label: {
                                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Ink.muted).frame(width: 32, height: 44)
                            }
                            .accessibilityLabel("Remove " + c + " from the list")
                        }
                    }
                }
            }
            TextField(label, text: Binding(get: { model.form.typed(kind) }, set: { model.form.setTyped(kind, $0) }))
                .focused($focus, equals: kind)
                .submitLabel(.done)
                .onSubmit { model.commitTyped(kind) }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line, lineWidth: 1))
        }
    }

    private func textSection(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            field(text: text, prompt: prompt)
        }
    }

    private func field(text: Binding<String>, prompt: String) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(2...6)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line, lineWidth: 1))
    }
}
