// ----------------------------------------
//  Lenis 慣性スクロールの初期化（スマホではオフ）
// ----------------------------------------
// document.addEventListener('DOMContentLoaded', function () {
//     // スマホ判定（iPhone / Android）
//     const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);

//     // PC のみ Lenis を有効化
//     if (typeof Lenis !== 'undefined' && !isMobile) {
//         const lenis = new Lenis({
//             smooth: true,
//             lerp: 0.1, // 慣性の強さ（0〜1で調整可能）
//         });

//         function raf(time) {
//             lenis.raf(time);
//             requestAnimationFrame(raf);
//         }

//         requestAnimationFrame(raf);
//     }
// });

// ----------------------------------------
//  バックボタン
// ----------------------------------------
document.querySelectorAll('.back_button').forEach(btn => {
    btn.addEventListener('click', e => {
    e.preventDefault();

    // 履歴があれば戻る
    if (window.history.length > 1) {
        window.history.back();
    } else {
        // 履歴がなければトップへ
        window.location.href = document.body.dataset.homeUrl;
    }
    });
});


(function($) {
    $(function(){  

    // ----------------------------------------
    // デバイス別判定関数
    // ----------------------------------------
    function isMobile() { return window.innerWidth <= 600;} // スマホ
    function isTablet() { return window.innerWidth > 601 && window.innerWidth <= 1140; } // タブレット
    function isDesktop() { return window.innerWidth > 1140; } // 1140px〜：PC

    // ----------------------------------------
    // サファリの時だけ .is-safari をhtmlに付与
    // ----------------------------------------
    var ua = navigator.userAgent.toLowerCase();
    var isSafari = ua.indexOf('safari') > -1 && ua.indexOf('chrome') === -1;
    if (isSafari) {
        $('html').addClass('is-safari');
    }

    // ----------------------------------------
    //  QAのトグル表示
    // ----------------------------------------
    $('.qa_item').on('click', function(){
        const q = $(this).find('.q');   // このアイテム内の .q
        const a = $(this).find('.a');   // このアイテム内の .a

        // 自分の a を開閉
        a.stop().slideToggle().toggleClass('open');

        // 他の a は閉じる
        $('.qa_item').not($(this)).find('.a').slideUp().removeClass('open');

        // q の active 制御
        q.toggleClass('active');
        $('.qa_item').not($(this)).find('.q').removeClass('active');
    });

    $(document).ready(function(){
        // すべて閉じる
        $('.a').hide();

        // 1番上の qa_item を初期から開く
        // const firstItem = $('.qa_item').first();
        // firstItem.find('.a').show().addClass('open');
        // firstItem.find('.q').addClass('active');
    });

        // ----------------
        // デバイス別判定関数
        // ----------------
        function isMobile() { return window.innerWidth <= 600;} // スマホ
        function isTablet() { return window.innerWidth > 601 && window.innerWidth <= 1140; } // タブレット
        function isDesktop() { return window.innerWidth > 1140; } // 1140px〜：PC



        // ----------------------------------------
        // シンプルなフェードアニメーション + 遅延対応
        //
        // fadeUpTriggerなどをつければフェードイン
        // fadeUp_late_200などをつければ200ms遅延（数値は任意）
        // ----------------------------------------
        function fadeAnime() {
          // 下から
        $('.fadeUpTrigger, [class*="fadeUp_trig_"]').each(function () {
            var $this = $(this);
            var elemPos = $this.offset().top;
            var scroll = $(window).scrollTop();
            var windowHeight = $(window).height();

            // トリガー位置（%） fadeUp_trig_50 → 0.5
            var trigClass = $this.attr('class').match(/fadeUp_trig_(\d+)/);
            var triggerPercent = trigClass ? parseInt(trigClass[1]) / 100 : 0.8; // デフォ80%
            var triggerPosition = scroll + windowHeight * triggerPercent;

            if (triggerPosition >= elemPos) {
                // 遅延クラス fadeUp_late_200
                var delayClass = $this.attr('class').match(/fadeUp_late_(\d+)/);
                if (delayClass) {
                $this.css('animation-delay', Number(delayClass[1]) + 'ms');
                }

                // 距離クラス fadeUp_dist_400
                var distClass = $this.attr('class').match(/fadeUp_dist_(\d+)/);
                if (distClass) {
                $this.css('--fadeUp-dist', Number(distClass[1]) + 'px');
                } else {
                $this.css('--fadeUp-dist', '200px'); // デフォ200px
                }

                // 時間クラス fadeUp_dur_1500
                var durClass = $this.attr('class').match(/fadeUp_dur_(\d+)/);
                if (durClass) {
                $this.css('--fadeUp-dur', Number(durClass[1]) + 'ms');
                } else {
                $this.css('--fadeUp-dur', '2000ms'); // デフォ2秒
                }

                // アニメーション発火
                $this.addClass('fadeUp');
            }
            });

            // 左から
            $('.fadeUpTrigger_left').each(function () {
                var elemPos = $(this).offset().top - 50;
                var scroll = $(window).scrollTop();
                var windowHeight = $(window).height();
                if (scroll >= elemPos - windowHeight) {
                $(this).addClass('fadeLeft');
                var delayClass = $(this).attr('class').match(/fadeLeft_late_(\d+)/);
                if (delayClass) {
                    $(this).css('animation-delay', Number(delayClass[1]) + 'ms');
                }
                }
            });

            // 右から
            $('.fadeUpTrigger_right').each(function () {
                var elemPos = $(this).offset().top - 50;
                var scroll = $(window).scrollTop();
                var windowHeight = $(window).height();
                if (scroll >= elemPos - windowHeight) {
                $(this).addClass('fadeRight');
                var delayClass = $(this).attr('class').match(/fadeRight_late_(\d+)/);
                if (delayClass) {
                    $(this).css('animation-delay', Number(delayClass[1]) + 'ms');
                }
                }
            });
            }

            // スクロール時に実行
            $(window).scroll(function () {
            fadeAnime();
        });

        // $(window).on('load', function () {
        //   fadeAnime();
        // });

        // $(window).on('scroll', function () {
        //     fadeAnime();
        // });



    });
})(jQuery);
