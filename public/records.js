$(function () {
  $('[data-toggle="popover"]').popover()
})

$('.toggler').on('click', function () {
	$(this).data('toggle-target').split(',').forEach(function(target) {
		$('.'+target).toggle();
	})
})