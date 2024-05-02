// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@TestOn('chrome || safari || firefox')
library;

import 'dart:typed_data';

import 'package:test/bootstrap/browser.dart';
import 'package:test/test.dart';
import 'package:ui/src/engine.dart' hide window;
import 'package:ui/ui.dart' as ui;
import 'package:ui/ui_web/src/ui_web.dart' as ui_web;

import '../../common/test_initialization.dart';
import 'semantics_tester.dart';

final InputConfiguration singlelineConfig = InputConfiguration(viewId: kImplicitViewId);

final InputConfiguration multilineConfig = InputConfiguration(
  viewId: kImplicitViewId,
  inputType: EngineInputType.multiline,
  inputAction: 'TextInputAction.newline',
);

EngineSemantics semantics() => EngineSemantics.instance;
EngineSemanticsOwner owner() => EnginePlatformDispatcher.instance.implicitView!.semantics;

const MethodCodec codec = JSONMethodCodec();

DateTime _testTime = DateTime(2021, 4, 16);

void main() {
  internalBootstrapBrowserTest(() => testMain);
}

void testMain() {
  setUpAll(() async {
    await bootstrapAndRunApp(withImplicitView: true);
  });

  setUp(() {
    EngineSemantics.debugResetSemantics();
  });

  group('$SemanticsTextEditingStrategy pre-initialization tests', () {
    setUp(() {
      semantics()
        ..debugOverrideTimestampFunction(() => _testTime)
        ..semanticsEnabled = true;
    });

    tearDown(() {
      semantics().semanticsEnabled = false;
    });

    test('Calling dispose() pre-initialization will not throw an error', () {
      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
        value: 'hi',
        isFocused: true,
      );
      final TextField textField = textFieldSemantics.primaryRole! as TextField;

      // ensureInitialized() isn't called prior to calling dispose() here.
      // Since we are conditionally calling dispose() on our
      // SemanticsTextEditingStrategy._instance, we shouldn't expect an error.
      // ref: https://github.com/flutter/engine/pull/40146
      expect(() => textField.dispose(), returnsNormally);
    });
  });

  group('$SemanticsTextEditingStrategy', () {
    late HybridTextEditing testTextEditing;
    late SemanticsTextEditingStrategy strategy;

    setUp(() {
      testTextEditing = HybridTextEditing();
      SemanticsTextEditingStrategy.ensureInitialized(testTextEditing);
      strategy = SemanticsTextEditingStrategy.instance;
      testTextEditing.debugTextEditingStrategyOverride = strategy;
      testTextEditing.configuration = singlelineConfig;
      semantics()
        ..debugOverrideTimestampFunction(() => _testTime)
        ..semanticsEnabled = true;
    });

    tearDown(() {
      semantics().semanticsEnabled = false;
    });

  test('renders a text field', () {
    createTextFieldSemantics(value: 'hello');

    expectSemanticsTree(owner(), '''
<sem style="$rootSemanticStyle">
  <input />
</sem>''');

    // TODO(yjbanov): this used to attempt to test that value="hello" but the
    //                test was a false positive. We should revise this test and
    //                make sure it tests the right things:
    //                https://github.com/flutter/flutter/issues/147200
    final SemanticsObject node = owner().debugSemanticsTree![0]!;
    expect(
      (node.element as DomHTMLInputElement).value,
      isNull,
    );
  });

    // TODO(yjbanov): this test will need to be adjusted for Safari when we add
    //                Safari testing.
    test('sends a didGainAccessibilityFocus/didLoseAccessibilityFocus action when browser requests focus/blur', () async {
      final SemanticsActionLogger logger = SemanticsActionLogger();
      createTextFieldSemantics(value: 'hello');

      final DomElement textField = owner().semanticsHost
          .querySelector('input[data-semantics-role="text-field"]')!;

      expect(owner().semanticsHost.ownerDocument?.activeElement, isNot(textField));

      textField.focus();

      expect(owner().semanticsHost.ownerDocument?.activeElement, textField);
      expect(await logger.idLog.first, 0);
      expect(await logger.actionLog.first, ui.SemanticsAction.didGainAccessibilityFocus);

      textField.blur();

      expect(owner().semanticsHost.ownerDocument?.activeElement, isNot(textField));
      expect(await logger.idLog.first, 0);
      expect(await logger.actionLog.first, ui.SemanticsAction.didLoseAccessibilityFocus);
    }, // TODO(yjbanov): https://github.com/flutter/flutter/issues/46638
       // TODO(yjbanov): https://github.com/flutter/flutter/issues/50590
    skip: ui_web.browser.browserEngine != ui_web.BrowserEngine.blink);

    test('Syncs semantic state from framework', () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      int changeCount = 0;
      int actionCount = 0;
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {
          changeCount++;
        },
        onAction: (_) {
          actionCount++;
        },
      );

      // Create
      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
        value: 'hello',
        label: 'greeting',
        isFocused: true,
        rect: const ui.Rect.fromLTWH(0, 0, 10, 15),
      );

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);
      expect(textField.editableElement, strategy.domElement);
      expect(textField.activeEditableElement.getAttribute('aria-label'), 'greeting');
      expect(textField.activeEditableElement.style.width, '10px');
      expect(textField.activeEditableElement.style.height, '15px');

      // Update
      createTextFieldSemantics(
        value: 'bye',
        label: 'farewell',
        rect: const ui.Rect.fromLTWH(0, 0, 12, 17),
      );

      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);
      expect(strategy.domElement, null);
      expect(textField.activeEditableElement.getAttribute('aria-label'), 'farewell');
      expect(textField.activeEditableElement.style.width, '12px');
      expect(textField.activeEditableElement.style.height, '17px');

      strategy.disable();

      // There was no user interaction with the <input> element,
      // so we should expect no engine-to-framework feedback.
      expect(changeCount, 0);
      expect(actionCount, 0);
    });

    test(
        'Does not overwrite text value and selection editing state on semantic updates',
        () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
          value: 'hello',
          textSelectionBase: 1,
          textSelectionExtent: 3,
          isFocused: true,
          rect: const ui.Rect.fromLTWH(0, 0, 10, 15));

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      final DomHTMLInputElement editableElement =
          textField.activeEditableElement as DomHTMLInputElement;

      expect(editableElement, strategy.domElement);
      expect(editableElement.value, '');
      expect(editableElement.selectionStart, 0);
      expect(editableElement.selectionEnd, 0);

      strategy.disable();
    });

    test(
        'Updates editing state when receiving framework messages from the text input channel',
        () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
          value: 'hello',
          textSelectionBase: 1,
          textSelectionExtent: 3,
          isFocused: true,
          rect: const ui.Rect.fromLTWH(0, 0, 10, 15));

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      final DomHTMLInputElement editableElement =
          textField.activeEditableElement as DomHTMLInputElement;

      // No updates expected on semantic updates
      expect(editableElement, strategy.domElement);
      expect(editableElement.value, '');
      expect(editableElement.selectionStart, 0);
      expect(editableElement.selectionEnd, 0);

      // Update from framework
      const MethodCall setEditingState =
          MethodCall('TextInput.setEditingState', <String, dynamic>{
        'text': 'updated',
        'selectionBase': 2,
        'selectionExtent': 3,
      });
      sendFrameworkMessage(codec.encodeMethodCall(setEditingState), testTextEditing);

      // Editing state should now be updated
      expect(editableElement.value, 'updated');
      expect(editableElement.selectionStart, 2);
      expect(editableElement.selectionEnd, 3);

      strategy.disable();
    });

    test('Gives up focus after DOM blur', () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
      );

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(textField.editableElement, strategy.domElement);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      // The input should not refocus after blur.
      textField.activeEditableElement.blur();
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);
      strategy.disable();
    });

    test('Does not dispose and recreate dom elements in persistent mode', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // It doesn't create a new DOM element.
      expect(strategy.domElement, isNull);

      // During the semantics update the DOM element is created and is focused on.
      final SemanticsObject textFieldSemantics = createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
      );
      expect(strategy.domElement, isNotNull);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.disable();
      expect(strategy.domElement, isNull);

      // It doesn't remove the DOM element.
      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(owner().semanticsHost.contains(textField.editableElement), isTrue);
      // Editing element is not enabled.
      expect(strategy.isEnabled, isFalse);
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);
    });

    test('Refocuses when setting editing state', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
      );
      expect(strategy.domElement, isNotNull);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      // Blur the element without telling the framework.
      strategy.activeDomElement.blur();
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      // The input will have focus after editing state is set and semantics updated.
      strategy.setEditingState(EditingState(text: 'foo'));

      // NOTE: at this point some browsers, e.g. some versions of Safari will
      //       have set the focus on the editing element as a result of setting
      //       the test selection range. Other browsers require an explicit call
      //       to `element.focus()` for the element to acquire focus. So far,
      //       this discrepancy hasn't caused issues, so we're not checking for
      //       any particular focus state between setEditingState and
      //       createTextFieldSemantics. However, this is something for us to
      //       keep in mind in case this causes issues in the future.

      createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
      );
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.disable();
    });

    test('Works in multi-line mode', () {
      strategy.enable(
        multilineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
        isMultiline: true,
      );

      final DomHTMLTextAreaElement textArea =
          strategy.domElement! as DomHTMLTextAreaElement;

      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      textArea.blur();
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      strategy.disable();
      // It doesn't remove the textarea from the DOM.
      expect(owner().semanticsHost.contains(textArea), isTrue);
      // Editing element is not enabled.
      expect(strategy.isEnabled, isFalse);
    });

    test('Does not position or size its DOM element', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // Send width and height that are different from semantics values on
      // purpose.
      final EditableTextGeometry geometry = EditableTextGeometry(
        height: 12,
        width: 13,
        globalTransform: Matrix4.translationValues(14, 15, 0).storage,
      );

      testTextEditing.acceptCommand(
        TextInputSetEditableSizeAndTransform(geometry: geometry),
        () {},
      );

      createTextFieldSemantics(
        value: 'hello',
        isFocused: true,
      );

      // Checks that the placement attributes come from semantics and not from
      // EditableTextGeometry.
      void checkPlacementIsSetBySemantics() {
        expect(strategy.activeDomElement.style.transform, '');
        expect(strategy.activeDomElement.style.width, '100px');
        expect(strategy.activeDomElement.style.height, '50px');
      }

      checkPlacementIsSetBySemantics();
      strategy.placeElement();
      checkPlacementIsSetBySemantics();
    });

    Map<int, SemanticsObject> createTwoFieldSemantics(SemanticsTester builder,
        {int? focusFieldId}) {
      builder.updateNode(
        id: 0,
        children: <SemanticsNodeUpdate>[
          builder.updateNode(
            id: 1,
            isTextField: true,
            value: 'Hello',
            isFocused: focusFieldId == 1,
            rect: const ui.Rect.fromLTRB(0, 0, 50, 10),
          ),
          builder.updateNode(
            id: 2,
            isTextField: true,
            value: 'World',
            isFocused: focusFieldId == 2,
            rect: const ui.Rect.fromLTRB(0, 20, 50, 10),
          ),
        ],
      );
      return builder.apply();
    }

    test('Changes focus from one text field to another through a semantics update', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // Switch between the two fields a few times.
      for (int i = 0; i < 5; i++) {
        final SemanticsTester tester = SemanticsTester(owner());
        createTwoFieldSemantics(tester, focusFieldId: 1);
        expect(tester.apply().length, 3);

        expect(owner().semanticsHost.ownerDocument?.activeElement,
            tester.getTextField(1).editableElement);
        expect(strategy.domElement, tester.getTextField(1).editableElement);

        createTwoFieldSemantics(tester, focusFieldId: 2);
        expect(tester.apply().length, 3);
        expect(owner().semanticsHost.ownerDocument?.activeElement,
            tester.getTextField(2).editableElement);
        expect(strategy.domElement, tester.getTextField(2).editableElement);
      }
    });
  }, skip: isIosSafari);

  group('$SemanticsTextEditingStrategy in iOS', () {
    late HybridTextEditing testTextEditing;
    late SemanticsTextEditingStrategy strategy;

    setUp(() {
      testTextEditing = HybridTextEditing();
      SemanticsTextEditingStrategy.ensureInitialized(testTextEditing);
      strategy = SemanticsTextEditingStrategy.instance;
      testTextEditing.debugTextEditingStrategyOverride = strategy;
      testTextEditing.configuration = singlelineConfig;
      ui_web.browser.debugBrowserEngineOverride = ui_web.BrowserEngine.webkit;
      ui_web.browser.debugOperatingSystemOverride = ui_web.OperatingSystem.iOs;
      semantics()
        ..debugOverrideTimestampFunction(() => _testTime)
        ..semanticsEnabled = true;
    });

    tearDown(() {
      ui_web.browser.debugBrowserEngineOverride = null;
      ui_web.browser.debugOperatingSystemOverride = null;
      semantics().semanticsEnabled = false;
    });

    test('does not render a text field', () {
      expect(owner().semanticsHost.querySelector('flt-semantics[role="textbox"]'), isNull);
      createTextFieldSemanticsForIos(value: 'hello');
      expect(owner().semanticsHost.querySelector('flt-semantics[role="textbox"]'), isNotNull);
    });

    test('tap detection works', () async {
      final SemanticsActionLogger logger = SemanticsActionLogger();
      createTextFieldSemanticsForIos(value: 'hello');

      final DomElement textField = owner().semanticsHost
          .querySelector('flt-semantics[role="textbox"]')!;

      simulateTap(textField);
      expect(await logger.idLog.first, 0);
      expect(await logger.actionLog.first, ui.SemanticsAction.tap);
    });

    test('Syncs semantic state from framework', () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      int changeCount = 0;
      int actionCount = 0;
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {
          changeCount++;
        },
        onAction: (_) {
          actionCount++;
        },
      );

      // Create
      final SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
        value: 'hello',
        label: 'greeting',
        isFocused: true,
        rect: const ui.Rect.fromLTWH(0, 0, 10, 15),
      );

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);
      expect(textField.editableElement, strategy.domElement);
      expect(textField.activeEditableElement.getAttribute('aria-label'), 'greeting');
      expect(textField.activeEditableElement.style.width, '10px');
      expect(textField.activeEditableElement.style.height, '15px');

      // Update
      createTextFieldSemanticsForIos(
        value: 'bye',
        label: 'farewell',
        rect: const ui.Rect.fromLTWH(0, 0, 12, 17),
      );
      final DomElement textBox =
          owner().semanticsHost.querySelector('flt-semantics[role="textbox"]')!;

      expect(strategy.domElement, null);
      expect(owner().semanticsHost.ownerDocument?.activeElement, textBox);
      expect(textBox.getAttribute('aria-label'), 'farewell');

      strategy.disable();

      // There was no user interaction with the <input> element,
      // so we should expect no engine-to-framework feedback.
      expect(changeCount, 0);
      expect(actionCount, 0);
    });

    test(
        'Does not overwrite text value and selection editing state on semantic updates',
        () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      final SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
          value: 'hello',
          textSelectionBase: 1,
          textSelectionExtent: 3,
          isFocused: true,
          rect: const ui.Rect.fromLTWH(0, 0, 10, 15));

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      final DomHTMLInputElement editableElement =
          textField.activeEditableElement as DomHTMLInputElement;

      expect(editableElement, strategy.domElement);
      expect(editableElement.value, '');
      expect(editableElement.selectionStart, 0);
      expect(editableElement.selectionEnd, 0);

      strategy.disable();
    });

    test(
        'Updates editing state when receiving framework messages from the text input channel',
        () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      final SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
          value: 'hello',
          textSelectionBase: 1,
          textSelectionExtent: 3,
          isFocused: true,
          rect: const ui.Rect.fromLTWH(0, 0, 10, 15));

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      final DomHTMLInputElement editableElement =
          textField.activeEditableElement as DomHTMLInputElement;

      // No updates expected on semantic updates
      expect(editableElement, strategy.domElement);
      expect(editableElement.value, '');
      expect(editableElement.selectionStart, 0);
      expect(editableElement.selectionEnd, 0);

      // Update from framework
      const MethodCall setEditingState =
          MethodCall('TextInput.setEditingState', <String, dynamic>{
        'text': 'updated',
        'selectionBase': 2,
        'selectionExtent': 3,
      });
      sendFrameworkMessage(codec.encodeMethodCall(setEditingState), testTextEditing);

      // Editing state should now be updated
      // expect(editableElement.value, 'updated');
      expect(editableElement.selectionStart, 2);
      expect(editableElement.selectionEnd, 3);

      strategy.disable();
    });

    test('Gives up focus after DOM blur', () {
      expect(owner().semanticsHost.ownerDocument?.activeElement, domDocument.body);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      final SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
      );

      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(textField.editableElement, strategy.domElement);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      // The input should not refocus after blur.
      textField.activeEditableElement.blur();
      final DomElement textBox =
          owner().semanticsHost.querySelector('flt-semantics[role="textbox"]')!;
      expect(owner().semanticsHost.ownerDocument?.activeElement, textBox);

      strategy.disable();
    });

    test('Disposes and recreates dom elements in persistent mode', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // It doesn't create a new DOM element.
      expect(strategy.domElement, isNull);

      // During the semantics update the DOM element is created and is focused on.
      final SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
      );
      expect(strategy.domElement, isNotNull);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.disable();
      expect(strategy.domElement, isNull);

      // It removes the DOM element.
      final TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(owner().semanticsHost.contains(textField.editableElement), isFalse);
      // Editing element is not enabled.
      expect(strategy.isEnabled, isFalse);
      // Focus is on the semantic object
      final DomElement textBox =
          owner().semanticsHost.querySelector('flt-semantics[role="textbox"]')!;
      expect(owner().semanticsHost.ownerDocument?.activeElement, textBox);
    });

    test('Refocuses when setting editing state', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
      );
      expect(strategy.domElement, isNotNull);
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      // Blur the element without telling the framework.
      strategy.activeDomElement.blur();
      final DomElement textBox =
          owner().semanticsHost.querySelector('flt-semantics[role="textbox"]')!;
      expect(owner().semanticsHost.ownerDocument?.activeElement, textBox);

      // The input will have focus after editing state is set and semantics updated.
      strategy.setEditingState(EditingState(text: 'foo'));

      // NOTE: at this point some browsers, e.g. some versions of Safari will
      //       have set the focus on the editing element as a result of setting
      //       the test selection range. Other browsers require an explicit call
      //       to `element.focus()` for the element to acquire focus. So far,
      //       this discrepancy hasn't caused issues, so we're not checking for
      //       any particular focus state between setEditingState and
      //       createTextFieldSemantics. However, this is something for us to
      //       keep in mind in case this causes issues in the future.

      createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
      );
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.disable();
    });

    test('Works in multi-line mode', () {
      strategy.enable(
        multilineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
        isMultiline: true,
      );

      final DomHTMLTextAreaElement textArea =
          strategy.domElement! as DomHTMLTextAreaElement;
      expect(owner().semanticsHost.ownerDocument?.activeElement, strategy.domElement);

      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      expect(owner().semanticsHost.contains(textArea), isTrue);

      textArea.blur();
      final DomElement textBox =
          owner().semanticsHost.querySelector('flt-semantics[role="textbox"]')!;

      expect(owner().semanticsHost.ownerDocument?.activeElement, textBox);

      strategy.disable();
      // It removes the textarea from the DOM.
      expect(owner().semanticsHost.contains(textArea), isFalse);
      // Editing element is not enabled.
      expect(strategy.isEnabled, isFalse);
    });

    test('Does not position or size its DOM element', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // Send width and height that are different from semantics values on
      // purpose.
      final Matrix4 transform = Matrix4.translationValues(14, 15, 0);
      final EditableTextGeometry geometry = EditableTextGeometry(
        height: 12,
        width: 13,
        globalTransform: transform.storage,
      );
      const ui.Rect semanticsRect = ui.Rect.fromLTRB(0, 0, 100, 50);

      testTextEditing.acceptCommand(
        TextInputSetEditableSizeAndTransform(geometry: geometry),
        () {},
      );

      createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
      );

      // Checks that the placement attributes come from semantics and not from
      // EditableTextGeometry.
      void checkPlacementIsSetBySemantics() {
        expect(strategy.activeDomElement.style.transform,
            isNot(equals(transform.toString())));
        expect(strategy.activeDomElement.style.width, '${semanticsRect.width}px');
        expect(strategy.activeDomElement.style.height, '${semanticsRect.height}px');
      }

      checkPlacementIsSetBySemantics();
      strategy.placeElement();
      checkPlacementIsSetBySemantics();
    });

    test('Changes focus from one text field to another through a semantics update', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );

      // Switch between the two fields a few times.
      for (int i = 0; i < 1; i++) {
        final SemanticsTester tester = SemanticsTester(owner());
        createTwoFieldSemanticsForIos(tester, focusFieldId: 1);

        expect(tester.apply().length, 3);
        expect(owner().semanticsHost.ownerDocument?.activeElement,
            tester.getTextField(1).editableElement);
        expect(strategy.domElement, tester.getTextField(1).editableElement);

        createTwoFieldSemanticsForIos(tester, focusFieldId: 2);
        expect(tester.apply().length, 3);
        expect(owner().semanticsHost.ownerDocument?.activeElement,
            tester.getTextField(2).editableElement);
        expect(strategy.domElement, tester.getTextField(2).editableElement);
      }
    });

    test('input transform is correct', () async {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      createTextFieldSemanticsForIos(
        value: 'hello',
        isFocused: true,
        );
      expect(strategy.activeDomElement.style.transform, 'translate(${offScreenOffset}px, ${offScreenOffset}px)');
      // See [_delayBeforePlacement].
      await Future<void>.delayed(const Duration(milliseconds: 120) , (){});
      expect(strategy.activeDomElement.style.transform, '');
    });

    test('disposes the editable element, if there is one', () {
      strategy.enable(
        singlelineConfig,
        onChange: (_, __) {},
        onAction: (_) {},
      );
      SemanticsObject textFieldSemantics = createTextFieldSemanticsForIos(
        value: 'hello',
      );
      TextField textField = textFieldSemantics.primaryRole! as TextField;
      expect(textField.editableElement, isNull);
      textField.dispose();
      expect(textField.editableElement, isNull);

      textFieldSemantics = createTextFieldSemanticsForIos(
        value: 'hi',
        isFocused: true,
      );
      textField = textFieldSemantics.primaryRole! as TextField;

      expect(textField.editableElement, isNotNull);
      textField.dispose();
      expect(textField.editableElement, isNull);
    });
  }, skip: !isSafari);
}


SemanticsObject createTextFieldSemantics({
  required String value,
  String label = '',
  bool isFocused = false,
  bool isMultiline = false,
  ui.Rect rect = const ui.Rect.fromLTRB(0, 0, 100, 50),
  int textSelectionBase = 0,
  int textSelectionExtent = 0,
}) {
  final SemanticsTester tester = SemanticsTester(owner());
  tester.updateNode(
    id: 0,
    label: label,
    value: value,
    isTextField: true,
    isFocused: isFocused,
    isMultiline: isMultiline,
    hasTap: true,
    rect: rect,
    textDirection: ui.TextDirection.ltr,
    textSelectionBase: textSelectionBase,
    textSelectionExtent: textSelectionExtent
  );
  tester.apply();
  return tester.getSemanticsObject(0);
}

void simulateTap(DomElement element) {
  element.dispatchEvent(createDomPointerEvent(
    'pointerdown',
    <Object?, Object?>{
      'clientX': 125,
      'clientY': 248,
    },
  ));
  element.dispatchEvent(createDomPointerEvent(
    'pointerup',
    <Object?, Object?>{
      'clientX': 126,
      'clientY': 248,
    },
  ));
}

/// An editable DOM element won't be created on iOS unless a tap is detected.
/// This function mimics the workflow by simulating a tap and sending a second
/// semantic update.
SemanticsObject createTextFieldSemanticsForIos({
  required String value,
  String label = '',
  bool isFocused = false,
  bool isMultiline = false,
  ui.Rect rect = const ui.Rect.fromLTRB(0, 0, 100, 50),
  int textSelectionBase = 0,
  int textSelectionExtent = 0,
}) {
  final SemanticsObject textFieldSemantics = createTextFieldSemantics(
    value: value,
    isFocused: isFocused,
    label: label,
    isMultiline: isMultiline,
    rect: rect,
    textSelectionBase: textSelectionBase,
    textSelectionExtent: textSelectionExtent,
  );

  if (isFocused) {
    final TextField textField = textFieldSemantics.primaryRole! as TextField;

    simulateTap(textField.semanticsObject.element);

    return createTextFieldSemantics(
      value: value,
      isFocused: isFocused,
      label: label,
      isMultiline: isMultiline,
      rect: rect,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
    );
  }
  return textFieldSemantics;
}

/// See [createTextFieldSemanticsForIos].
Map<int, SemanticsObject> createTwoFieldSemanticsForIos(SemanticsTester builder,
    {int? focusFieldId}) {
  builder.updateNode(
    id: 0,
    children: <SemanticsNodeUpdate>[
      builder.updateNode(
        id: 1,
        isTextField: true,
        value: 'Hello',
        label: 'Hello',
        isFocused: false,
        rect: const ui.Rect.fromLTWH(0, 0, 10, 10),
      ),
      builder.updateNode(
        id: 2,
        isTextField: true,
        value: 'World',
        label: 'World',
        isFocused: false,
        rect: const ui.Rect.fromLTWH(20, 20, 10, 10),
      ),
    ],
  );
  builder.apply();
  final String label = focusFieldId == 1 ? 'Hello' : 'World';
  final DomElement textBox =
      owner().semanticsHost.querySelector('flt-semantics[aria-label="$label"]')!;

  simulateTap(textBox);

  builder.updateNode(
    id: 0,
    children: <SemanticsNodeUpdate>[
      builder.updateNode(
        id: 1,
        isTextField: true,
        value: 'Hello',
        label: 'Hello',
        isFocused: focusFieldId == 1,
        rect: const ui.Rect.fromLTWH(0, 0, 10, 10),
      ),
      builder.updateNode(
        id: 2,
        isTextField: true,
        value: 'World',
        label: 'World',
        isFocused: focusFieldId == 2,
        rect: const ui.Rect.fromLTWH(20, 20, 10, 10),
      ),
    ],
  );
  return builder.apply();
}

/// Emulates sending of a message by the framework to the engine.
void sendFrameworkMessage(ByteData? message, HybridTextEditing testTextEditing) {
  testTextEditing.channel.handleTextInput(message, (ByteData? data) {});
}
