# 店舗向けFAQの正本と同期手順

## 正本

店舗向けFAQの文面は、次のGoogleドキュメントを正本とする。

- [Butterflyve 店舗向けFAQ](https://docs.google.com/document/d/1Ud0SYSN4ej0Gr-Rag49f0fS1fbmNJ4XrUxw6PDwzmdQ/edit)

アプリでは外部APIへ実行時にアクセスせず、`StoreFaqCatalog`にFAQを保持する。

## 更新手順

1. 正本のGoogleドキュメントから最新の全文を取得する。
2. 分類名、質問番号、質問文、回答の段落と箇条書きを`StoreFaqCatalog`と照合する。
3. 正本に差分がある場合は、表現を補足・要約せず、そのまま`StoreFaqCatalog`へ反映する。
4. Q番号がQ1から連番であること、分類数と質問数が正本と一致することを確認する。
5. `test/integration/store_faq_test.rb`を実行し、公開ページの全質問と主要な実装説明が表示されることを確認する。
6. PC・タブレット・スマートフォンで分類の切り替えと質問の開閉を確認する。
7. JavaScriptを無効にした状態で、すべての分類と質問が表示されることを確認する。

文面を先にコードだけで変更しない。正本を更新したうえで、同じ変更をコードへ同期する。
