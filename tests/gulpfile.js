var gulp = require('gulp');
var concat = require('gulp-concat');

var paths = {
    scripts: ['*.js']
};

gulp.task('default', function() {
    return gulp.src(paths.scripts)
        .pipe(concat('all.min.js'))
        .pipe(gulp.dest('build'));
});